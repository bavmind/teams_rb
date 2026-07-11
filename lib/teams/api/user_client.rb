# frozen_string_literal: true

require "uri"

module Teams
  module Api
    # User token operations against the Bot Framework token service (a
    # different host than the conversation service). Requires an OAuth
    # connection configured on the bot registration.
    class UserClient
      attr_reader :oauth_url, :http

      def initialize(oauth_url:, http:, logger: nil)
        @oauth_url = oauth_url.sub(%r{/+\z}, "")
        @http = http
        @logger = logger
      end

      def get_token(user_id:, connection_name:, channel_id: nil, code: nil)
        url = endpoint(
          "api/usertoken/GetToken",
          "userId" => user_id, "connectionName" => connection_name,
          "channelId" => channel_id, "code" => code
        )
        @logger&.debug("Teams API GET #{url}")
        TokenResponse.new(http.get(url))
      end

      def get_aad_tokens(user_id:, connection_name:, resource_urls:, channel_id:)
        # resourceUrls are repeated query keys on the wire (Python's shape);
        # the array goes through params: so the flat encoder handles it —
        # hand-built query strings get re-encoded by Faraday, which would
        # collapse repeated keys.
        url = "#{oauth_url}/api/usertoken/GetAadTokens"
        @logger&.debug("Teams API POST #{url}")
        response = http.post(url, params: {
          "userId" => user_id,
          "connectionName" => connection_name,
          "channelId" => channel_id,
          "resourceUrls" => Array(resource_urls)
        })
        (response || {}).transform_values { |value| TokenResponse.new(value) }
      end

      def get_token_status(user_id:, channel_id:, include_filter: nil)
        url = endpoint(
          "api/usertoken/GetTokenStatus",
          "userId" => user_id, "channelId" => channel_id, "includeFilter" => include_filter
        )
        @logger&.debug("Teams API GET #{url}")
        Array(http.get(url)).map { |status| TokenStatus.new(status) }
      end

      def sign_out(user_id:, connection_name:, channel_id:)
        url = endpoint(
          "api/usertoken/SignOut",
          "userId" => user_id, "connectionName" => connection_name, "channelId" => channel_id
        )
        @logger&.debug("Teams API DELETE #{url}")
        http.delete(url)
        nil
      end

      # exchange_request carries either a token exchange token (SSO) or a
      # uri: {"token" => ...} or {"uri" => ...}.
      def exchange_token(user_id:, connection_name:, channel_id:, exchange_request:)
        url = endpoint(
          "api/usertoken/exchange",
          "userId" => user_id, "connectionName" => connection_name, "channelId" => channel_id
        )
        @logger&.debug("Teams API POST #{url}")
        TokenResponse.new(http.post(url, json: Common::Hashes.deep_stringify_keys(exchange_request)))
      end

      private

      def endpoint(path, params)
        query = URI.encode_www_form(params.compact)
        "#{oauth_url}/#{path}?#{query}"
      end
    end
  end
end
