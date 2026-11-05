# frozen_string_literal: true

require "faraday"
require "uri"

module Teams
  module Files
    # The minimal description the downloader needs to open a file's bytes.
    FetchTarget = Struct.new(:scope, :download_url, :content_url, :content_type, :attachment_style, keyword_init: true)

    # What a successful fetch resolved: where the bytes came from and their
    # MIME type (the response's, else the file's, else octet-stream).
    OpenedFile = Struct.new(:source_url, :content_type, keyword_init: true)

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

      def initialize(connection: nil, logger: nil)
        @connection = connection || Faraday.new
        @logger = logger
      end

      # Streams target's bytes to the block and returns an OpenedFile.
      def fetch(target, prior_fetch_succeeded: false, &on_chunk)
        if target.scope == "personal"
          return fetch_personal(target, prior_fetch_succeeded:, &on_chunk)
        end

        raise FileScopeNotSupportedError, target.scope
      end

      private

      def fetch_personal(target, prior_fetch_succeeded:, &on_chunk)
        url = target.download_url
        raise Error, "cannot download file: no download URL is available" unless url
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
