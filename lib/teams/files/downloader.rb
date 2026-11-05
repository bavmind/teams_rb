# frozen_string_literal: true

require "base64"
require "faraday"
require "json"
require "uri"

module Teams
  module Files
    # The minimal description the downloader needs to open a file's bytes.
    FetchTarget = Struct.new(:scope, :download_url, :content_url, :content_type, :attachment_style, keyword_init: true)

    # What a successful fetch resolved: where the bytes came from and their
    # MIME type (the response's, else the file's, else octet-stream).
    OpenedFile = Struct.new(:source_url, :content_type, keyword_init: true)

    # The Graph credential for a turn's file reads: actor names the identity
    # ("app" or "agentic_user"), token is a callable resolved only when a
    # Graph read happens, base_url_root the Graph host root.
    GraphCredential = Struct.new(:actor, :token, :base_url_root, keyword_init: true)

    # The Bot API credential for reading pasted inline images: the turn's API
    # token (an agentic identity reads as itself), resolved lazily, and the
    # activity's service URL — the token is only ever sent under it.
    BotApiCredential = Struct.new(:actor, :token, :service_url, keyword_init: true)

    # Fetches inbound file bytes, keyed on the conversation scope so every
    # scope's receive path extends this one place, like the TypeScript,
    # Python, and .NET dispatchers.
    #
    # It holds a plain Faraday connection with no token middleware: a
    # pre-authorized download URL carries its own tempauth credential, so the
    # bot's Authorization header must never reach the storage host (Python
    # strips it from its shared client for the same reason).
    class Downloader
      OCTET_STREAM = "application/octet-stream"
      MAX_REDIRECTS = 20
      # How much of an error body to keep for diagnostics.
      ERROR_BODY_LIMIT = 2048
      REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze

      Response = Struct.new(:status, :headers, :reason_phrase, :error_body, keyword_init: true)

      GRAPH_FILE_PERMISSION_PREFIXES = %w[files. sites.].freeze

      # Whether a file that arrived with only a content URL may be read
      # through Graph in this scope, as this actor. Shared by the accessor and
      # the dispatcher so a file list surfaces is always one download opens.
      # Personal is open to every actor; group chats and channels only to an
      # agentic user, the only identity the platform delivers files to there.
      def self.graph_route_open?(scope, actor)
        return true if scope == "personal"

        actor == "agentic_user" && %w[groupChat channel].include?(scope)
      end

      SINGLE_DOT_SEGMENTS = %w[. %2e].freeze
      DOUBLE_DOT_SEGMENTS = %w[.. .%2e %2e. %2e%2e].freeze
      PERCENT_ESCAPE = /%[0-9A-Fa-f]{2}/

      # Whether url is under service_url: both https, the same origin, and a
      # path inside the service URL's path. Dot segments (including
      # percent-encoded dots) are resolved first so a path cannot climb out;
      # scheme and host compare case-insensitively, the path case-sensitively
      # apart from percent-escape hex digits.
      def self.under_service_url?(url, service_url)
        return false if service_url.nil? || service_url.empty?

        target = URI.parse(url)
        base = URI.parse(service_url)
        return false unless base.scheme&.downcase == "https"
        return false unless [target.scheme&.downcase, target.host&.downcase, target.port] ==
          [base.scheme.downcase, base.host&.downcase, base.port]

        # Exactly one trailing slash, so /amer cannot match /americas.
        base_path = normalize_percent_escapes("#{resolve_dot_segments(base.path).sub(%r{/+\z}, "")}/")
        normalize_percent_escapes(resolve_dot_segments(target.path)).start_with?(base_path)
      rescue URI::Error
        false
      end

      def self.resolve_dot_segments(path)
        resolved = []
        path.to_s.sub(%r{\A/+}, "").split("/", -1).each do |segment|
          folded = segment.downcase
          next if SINGLE_DOT_SEGMENTS.include?(folded)

          if DOUBLE_DOT_SEGMENTS.include?(folded)
            resolved.pop
            next
          end
          resolved << segment
        end
        "/#{resolved.join("/")}"
      end

      def self.normalize_percent_escapes(path)
        path.gsub(PERCENT_ESCAPE, &:upcase)
      end

      def initialize(connection: nil, logger: nil)
        @connection = connection || Faraday.new
        @logger = logger
      end

      # Streams target's bytes to the block and returns an OpenedFile.
      # Personal files take either route; elsewhere only the Graph route, and
      # only where graph_route_open? allows. A download URL outside personal
      # keeps the scope error: Graph is never substituted for a URL the
      # platform supplied.
      def fetch(target, prior_fetch_succeeded: false, credential: nil, bot_api_credential: nil, &on_chunk)
        # Inline images live on the Bot API, so neither file route nor its
        # scope restriction applies.
        if target.attachment_style == "inlineImage"
          return fetch_inline_image(target, credential: bot_api_credential, &on_chunk)
        end

        if target.scope == "personal"
          return fetch_personal(target, prior_fetch_succeeded:, credential:, &on_chunk)
        end

        if target.download_url.nil? && target.content_url && self.class.graph_route_open?(target.scope, credential&.actor)
          return fetch_graph(target, target.content_url, credential:, &on_chunk)
        end

        raise FileScopeNotSupportedError, target.scope
      end

      private

      def fetch_personal(target, prior_fetch_succeeded:, credential:, &on_chunk)
        url = target.download_url
        # The agentic user case: a browsable content URL arrives instead of a
        # download URL, so Graph is the only route to the bytes.
        unless url
          raise Error, "cannot download file: no download URL is available" unless target.content_url

          return fetch_graph(target, target.content_url, credential:, &on_chunk)
        end

        if credential&.actor == "agentic_user"
          @logger&.warn(
            "an agentic turn received a file carrying a pre-authorized download URL, which the platform did not " \
            "previously send to agents. The SDK is using that URL, so these bytes are not attributed to the " \
            "agentic user."
          )
        end
        raise Error, "cannot download file: download URL must use https" unless url.downcase.start_with?("https://")

        # Plain GET with no bearer token: the URL embeds its own credential.
        response = get_following_https_redirects(url, {}, &on_chunk)
        if [401, 403].include?(response.status)
          # Terminal: the URL's own credential lapsed, and the SDK does not fall
          # back to another identity. The file has to be sent again.
          raise FileUrlExpiredError, (prior_fetch_succeeded ? "reread" : "first_fetch")
        end
        unless success?(response.status)
          raise Error, "failed to download file: #{response.status} #{response.reason_phrase}".strip
        end

        opened(url, response, target)
      end

      # Reads the bytes through Graph /shares as the credential's identity.
      # Unlike the pre-authorized route this is an ordinary authenticated Graph
      # call, and a missing consent is detected before the request.
      def fetch_graph(target, sharing_url, credential:, &on_chunk)
        actor = credential&.actor
        token, failure = resolve_graph_token(credential)
        raise FileCredentialError.new(actor, failure) if token.to_s.empty? || carries_no_graph_permissions?(token)

        url = GraphShare.drive_item_content_url(sharing_url, credential.base_url_root || "https://graph.microsoft.com")
        @logger&.debug("files: resolving bytes through Graph /shares as '#{actor}'")

        response = get_following_https_redirects(url, { "Authorization" => "Bearer #{token}" }, &on_chunk)
        if [401, 403].include?(response.status)
          raise FileAccessError.new(response.status, actor, service_error(response.error_body))
        end
        unless success?(response.status)
          details = service_error(response.error_body)
          message = "failed to download file through Graph as '#{actor || "app"}': " \
            "#{response.status} #{response.reason_phrase}".strip
          raise Error, details ? "#{message} (#{details})" : message
        end

        opened(url, response, target)
      end

      # Reads an inline image from the Bot API with the turn's Bot API token,
      # sent only to a URL under the activity's service URL.
      def fetch_inline_image(target, credential:, &on_chunk)
        url = target.content_url
        raise Error, "cannot download inline image: no content URL is available" unless url
        raise Error, "cannot download inline image: content URL must use https" unless url.downcase.start_with?("https://")
        raise Error, "cannot download inline image: no Bot API token is available" unless credential
        unless self.class.under_service_url?(url, credential.service_url)
          raise Error, "cannot download inline image: content URL is not under the activity's service URL"
        end

        actor = credential.actor
        token = credential.token ? credential.token.call.to_s.strip : ""
        raise Error, "cannot download inline image: no Bot API token is available" if token.empty?

        @logger&.debug("files: reading inline image bytes from the Bot API as '#{actor}'")
        response = get_following_https_redirects(url, { "Authorization" => "Bearer #{token}" }, &on_chunk)
        if response.status == 415
          raise InlineImageTransformationError.new(
            response.status, actor, service_error(response.error_body), service_error_code(response.error_body)
          )
        end
        if [401, 403].include?(response.status)
          raise InlineImageAccessError.new(response.status, actor, service_error(response.error_body))
        end
        unless success?(response.status)
          details = service_error(response.error_body)
          message = "failed to download inline image as '#{actor}': #{response.status} #{response.reason_phrase}".strip
          raise Error, details ? "#{message} (#{details})" : message
        end

        opened(url, response, target)
      end

      def service_error_code(raw)
        return nil if raw.nil? || raw.empty?

        envelope = JSON.parse(raw.dup.force_encoding(Encoding::UTF_8).scrub)
        code = envelope.dig("error", "code") if envelope.is_a?(Hash) && envelope["error"].is_a?(Hash)
        code.is_a?(String) && !code.strip.empty? ? code.strip : nil
      rescue JSON::ParserError
        nil
      end

      # Resolves the token without raising: an acquisition failure degrades to
      # "no token" with its reason, so it reports as a credential problem.
      def resolve_graph_token(credential)
        return [nil, nil] unless credential&.token

        [credential.token.call, nil]
      rescue StandardError => error
        @logger&.debug("files: could not acquire a Graph token: #{error.message}")
        [nil, error.message]
      end

      # A token that decodes but carries no Files.* or Sites.* permission
      # cannot reach a drive item; Graph would answer with an ambiguous 401 or
      # 403. Fails open on an undecodable token (the call proceeds).
      def carries_no_graph_permissions?(token)
        permissions = token_permissions(token)
        return false if permissions.nil?

        permissions.none? do |permission|
          GRAPH_FILE_PERMISSION_PREFIXES.any? { |prefix| permission.downcase.start_with?(prefix) }
        end
      end

      # App-only tokens list application permissions in roles; delegated and
      # agentic-user tokens list scopes in scp. nil means undecodable.
      def token_permissions(token)
        payload = token.split(".")[1]
        return nil unless payload

        claims = JSON.parse(Base64.urlsafe_decode64(payload + ("=" * (-payload.length % 4))))
        return nil unless claims.is_a?(Hash)

        roles = claims["roles"].is_a?(Array) ? claims["roles"].grep(String) : []
        scopes = claims["scp"].is_a?(String) ? claims["scp"].split : []
        roles + scopes
      rescue ArgumentError, JSON::ParserError, EncodingError
        nil
      end

      # The readable part of a Graph error envelope ({"error": {"code",
      # "message"}}), falling back to the raw text; a 401 from the edge can be
      # HTML.
      def service_error(raw)
        return nil if raw.nil? || raw.empty?

        text = raw.dup.force_encoding(Encoding::UTF_8).scrub
        begin
          envelope = JSON.parse(text)
          error = envelope["error"] if envelope.is_a?(Hash)
          if error.is_a?(Hash)
            parts = [error["code"], error["message"]].select { |part| part && !part.to_s.empty? }.map(&:to_s)
            return truncate(parts.join(": ")) unless parts.empty?
          end
        rescue JSON::ParserError
          nil
        end
        truncate(text)
      end

      def truncate(text)
        collapsed = text.split.join(" ")
        return nil if collapsed.empty?

        collapsed.length > ERROR_BODY_LIMIT ? "#{collapsed[0, ERROR_BODY_LIMIT]}..." : collapsed
      end

      def opened(url, response, target)
        OpenedFile.new(
          source_url: url,
          content_type: response.headers["content-type"] || target.content_type || OCTET_STREAM
        )
      end

      # Storage answers with a redirect to the host holding the bytes, so
      # redirects are followed, one hop at a time so a downgrade to plaintext
      # can be refused. Authorization is dropped when a hop leaves the origin.
      def get_following_https_redirects(url, headers, &on_chunk)
        current = url
        headers = headers.dup
        response = perform_get(current, headers, &on_chunk)
        MAX_REDIRECTS.times do
          location = response.headers["location"]
          return response unless REDIRECT_STATUSES.include?(response.status) && location

          next_url = URI.join(current, location).to_s
          next_uri = URI.parse(next_url)
          unless next_uri.scheme&.downcase == "https"
            raise Error, "cannot download file: a redirect destination must use https, got " \
              "'#{next_uri.scheme}://#{next_uri.host}'. The file's bytes would cross that hop in the clear."
          end

          headers.delete("Authorization") unless same_origin?(current, next_uri)
          current = next_url
          response = perform_get(current, headers, &on_chunk)
        end
        raise Error, "cannot download file: too many redirects" if REDIRECT_STATUSES.include?(response.status)

        response
      rescue URI::Error => error
        raise Error, "cannot download file: invalid redirect location (#{error.message})"
      end

      # One GET. Success bodies stream to the block as they arrive; any other
      # body is kept, capped, for the error message. Adapters that do not
      # stream (such as Faraday's test adapter) hand the whole body over once.
      def perform_get(url, headers, &on_chunk)
        status = nil
        streamed = false
        error_body = +"".b

        response = @connection.get(url) do |request|
          request.headers.update(headers)
          request.options.on_data = proc do |chunk, _received, env|
            status ||= env.status
            next if chunk.empty?

            if success?(status)
              streamed = true
              on_chunk&.call(chunk)
            else
              append_capped(error_body, chunk)
            end
          end
        end

        body = response.body
        if body.is_a?(String) && !body.empty?
          if success?(response.status)
            on_chunk&.call(body) unless streamed
          elsif error_body.empty?
            append_capped(error_body, body)
          end
        end

        Response.new(
          status: response.status,
          headers: response.headers,
          reason_phrase: response.reason_phrase,
          error_body:
        )
      rescue Faraday::Error => error
        raise Error, "failed to download file: #{error.message}"
      end

      def append_capped(buffer, chunk)
        remaining = ERROR_BODY_LIMIT - buffer.bytesize
        buffer << chunk.byteslice(0, remaining).b if remaining.positive?
      end

      def success?(status)
        status.is_a?(Integer) && status.between?(200, 299)
      end

      def same_origin?(url, other)
        uri = URI.parse(url)
        [uri.scheme&.downcase, uri.host&.downcase, uri.port] == [other.scheme&.downcase, other.host&.downcase, other.port]
      end
    end
  end
end
