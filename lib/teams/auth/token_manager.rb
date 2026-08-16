# frozen_string_literal: true

require "uri"

module Teams
  module Auth
    class TokenManager
      TOKEN_EXCHANGE_SCOPE = "api://AzureADTokenExchange/.default"
      CLIENT_ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
      JWT_BEARER_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:jwt-bearer"

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

      # Agent 365 tokens use a three-step exchange (the other SDKs delegate
      # it to MSAL; Ruby implements the grants directly):
      #   1. client-credentials with fmi_path=<agenticAppId> for the token
      #      exchange scope - the blueprint assertion.
      #   2. client-credentials as client_id=<agenticAppId>, authenticated
      #      by the step-1 assertion - the agentic app token.
      #   3. the user federated-identity grant (requested_token_use
      #      on_behalf_of, user_object_id=<agenticUserId>), asserted by a
      #      step-2 exchange token - the agentic user token.
      # LIVE-VERIFY: steps 1 and 3 reproduce MSAL-internal wire forms from
      # its documented parameters; they have not yet been verified against
      # a live Agent 365 tenant. Do not release before verifying.
      # There is deliberately no app-token fallback: failing is safer than
      # authenticating under the wrong identity, like the other SDKs.
      def agentic_app_token(scope, agentic_app_id:, tenant_id: nil)
        tenant = resolve_agentic_tenant!(tenant_id)
        raise ArgumentError, "agentic_app_id is required for agentic tokens" if agentic_app_id.to_s.empty?

        @mutex.synchronize do
          cached_token([:agentic_app, scope, agentic_app_id, tenant]) do
            acquire_agentic_app_token(scope, agentic_app_id, tenant)
          end
        end
      end

      def agentic_user_token(scope, agentic_app_id:, agentic_user_id:, tenant_id: nil)
        tenant = resolve_agentic_tenant!(tenant_id)
        raise ArgumentError, "agentic_app_id is required for agentic tokens" if agentic_app_id.to_s.empty?
        raise ArgumentError, "agentic_user_id is required for agentic user tokens" if agentic_user_id.to_s.empty?

        @mutex.synchronize do
          cached_token([:agentic_user, scope, agentic_app_id, agentic_user_id, tenant]) do
            exchange_token = acquire_agentic_app_token(TOKEN_EXCHANGE_SCOPE, agentic_app_id, tenant)
            response = http.post(
              token_url(tenant),
              body: URI.encode_www_form(
                grant_type: JWT_BEARER_GRANT_TYPE,
                client_id: agentic_app_id,
                client_assertion_type: CLIENT_ASSERTION_TYPE,
                client_assertion: blueprint_assertion(agentic_app_id, tenant),
                assertion: exchange_token,
                requested_token_use: "on_behalf_of",
                user_object_id: agentic_user_id,
                scope:
              ),
              headers: FORM_HEADERS
            )
            fetch_access_token!(response, "Agent token exchange step 3 failed")
          end
        end
      end

      private

      FORM_HEADERS = { "Content-Type" => "application/x-www-form-urlencoded" }.freeze

      def token_url(tenant_id)
        "#{cloud.login_endpoint}/#{tenant_id}/oauth2/v2.0/token"
      end

      # Agentic tenant resolution is strict: the identity's tenant or the
      # configured credentials tenant, never the shared login tenant.
      def resolve_agentic_tenant!(tenant_id)
        raise ConfigurationError, "CLIENT_ID and CLIENT_SECRET are required" unless credentials

        tenant = tenant_id || credentials.tenant_id
        raise ArgumentError, "tenant_id is required for agentic tokens" if tenant.to_s.empty?

        tenant
      end

      def cached_token(key)
        cached = @tokens[key]
        return cached.value if cached && !cached.expired?

        token = yield
        @tokens[key] = Token.new(token)
        token
      end

      # Step 1: the blueprint assertion - the app's own client-credentials
      # grant carrying MSAL's federated-managed-identity path parameter.
      # Cached like any token so multi-step flows reuse it while valid.
      def blueprint_assertion(agentic_app_id, tenant_id)
        cached_token([:blueprint_assertion, agentic_app_id, tenant_id]) do
          request_blueprint_assertion(agentic_app_id, tenant_id)
        end
      end

      def request_blueprint_assertion(agentic_app_id, tenant_id)
        response = http.post(
          token_url(tenant_id),
          body: URI.encode_www_form(
            grant_type: "client_credentials",
            client_id: credentials.client_id,
            client_secret: credentials.client_secret,
            scope: TOKEN_EXCHANGE_SCOPE,
            fmi_path: agentic_app_id
          ),
          headers: FORM_HEADERS
        )
        fetch_access_token!(response, "Agent token exchange step 1 failed")
      end

      # Step 2: client-credentials as the agentic app, authenticated by the
      # step-1 assertion instead of a secret.
      def acquire_agentic_app_token(scope, agentic_app_id, tenant_id)
        response = http.post(
          token_url(tenant_id),
          body: URI.encode_www_form(
            grant_type: "client_credentials",
            client_id: agentic_app_id,
            client_assertion_type: CLIENT_ASSERTION_TYPE,
            client_assertion: blueprint_assertion(agentic_app_id, tenant_id),
            scope:
          ),
          headers: FORM_HEADERS
        )
        fetch_access_token!(response, "Agent token exchange step 2 failed")
      end

      def fetch_access_token!(response, error_prefix)
        token = response["access_token"] if response.is_a?(Hash)
        return token unless token.to_s.empty?

        detail = response.is_a?(Hash) ? response["error_description"] || response["error"] : nil
        raise Error, "#{error_prefix}: #{detail || "could not acquire token"}"
      end
    end
  end
end
