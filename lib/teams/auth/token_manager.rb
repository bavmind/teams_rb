# frozen_string_literal: true

require "uri"

module Teams
  module Auth
    class TokenManager
      attr_reader :credentials, :cloud, :http

      def initialize(credentials:, cloud: PUBLIC_CLOUD, http: nil)
        @credentials = credentials
        @cloud = cloud
        @http = http || Common::HttpClient.new
        @tokens = {}
        # One app-wide manager is shared across request threads; the mutex
        # prevents concurrent refreshes of the same token (the other SDKs
        # get this from MSAL, which locks internally).
        @mutex = Mutex.new
      end

      def self.from_env(
        client_id: ENV["CLIENT_ID"],
        client_secret: ENV["CLIENT_SECRET"],
        tenant_id: ENV["TENANT_ID"],
        cloud: PUBLIC_CLOUD,
        http: nil
      )
        credentials = if client_id && client_secret
          ClientSecretCredentials.new(client_id:, client_secret:, tenant_id:)
        end

        new(credentials:, cloud:, http:)
      end

      def client_id
        credentials&.client_id
      end

      def bot_token
        token_for(cloud.bot_scope, credentials&.tenant_id || cloud.login_tenant)
      end

      def token_for(scope, tenant_id)
        @mutex.synchronize do
          cached = @tokens[[scope, tenant_id]]
          return cached.value if cached && !cached.expired?

          raise ConfigurationError, "CLIENT_ID and CLIENT_SECRET are required" unless credentials

          response = http.post(
            "#{cloud.login_endpoint}/#{tenant_id}/oauth2/v2.0/token",
            body: URI.encode_www_form(
              client_id: credentials.client_id,
              client_secret: credentials.client_secret,
              scope:,
              grant_type: "client_credentials"
            ),
            headers: { "Content-Type" => "application/x-www-form-urlencoded" }
          )

          access_token = response.fetch("access_token")
          @tokens[[scope, tenant_id]] = Token.new(access_token)
          access_token
        end
      end
    end
  end
end
