# frozen_string_literal: true

require "jwt"
require "jwk-loader"

module Teams
  module Auth
    class JwtValidator
      ENTRA_V1_ISSUER_PREFIX = "https://sts.windows.net/"
      JWKS_CACHE_MAX_AGE = 10 * 60
      # Endpoints are bounded so random tenant ids in unverified inbound
      # tokens cannot grow the JWKS caches forever, like the
      # TypeScript/Python validators.
      MAX_JWKS_ENDPOINTS = 100
      CLOCK_TOLERANCE = 5 * 60

      def initialize(client_id:, tenant_id: nil, cloud: PUBLIC_CLOUD, http: nil)
        @client_id = client_id
        @tenant_id = tenant_id
        @cloud = cloud
        @http = http || Common::HttpClient.new
        @jwks_loaders = {}
        @jwks_mutex = Mutex.new
        @discovery_mutex = Mutex.new
      end

      def validate!(authorization_header, service_url: nil)
        token = bearer_token!(authorization_header)
        payload = decode!(token, issuers: valid_issuers) do |header, claims|
          signing_key(jwks_uri_for_issuer(claims["iss"]), header["kid"])
        end
        validate_service_url!(payload, service_url) if service_url
        payload
      end

      # Validates an inbound activity token. Classic bot activities carry
      # Bot Framework service tokens and validate exactly like validate!;
      # Agent 365 activities carry Entra tokens audienced to the agentic app
      # blueprint, validated against the token's own tenant. The Entra path
      # skips the serviceurl claim: agentic inbound tokens do not carry it
      # (upstream revisits once the platform defines a signed equivalent).
      def validate_inbound_activity!(authorization_header, service_url: nil)
        token = bearer_token!(authorization_header)
        claims = unverified_claims(token)
        return validate_entra_inbound!(token, claims) if entra_issuer?(claims["iss"])

        payload = decode!(token, issuers: valid_issuers) do |header, decoded|
          signing_key(jwks_uri_for_issuer(decoded["iss"]), header["kid"])
        end
        validate_service_url!(payload, service_url) if service_url
        payload
      end

      private

      def bearer_token!(authorization_header)
        raise AuthenticationError, "Authorization header is required" if authorization_header.to_s.empty?

        scheme, token = authorization_header.split(" ", 2)
        raise AuthenticationError, "Authorization must be Bearer" unless scheme&.casecmp("Bearer")&.zero? && token

        token
      end

      def decode!(token, issuers:)
        payload, = JWT.decode(
          token, nil, true,
          algorithms: ["RS256"], leeway: CLOCK_TOLERANCE,
          verify_expiration: true, verify_not_before: true,
          verify_iss: true, iss: issuers,
          verify_aud: true, aud: valid_audiences
        ) do |header, claims|
          raise AuthenticationError, "JWT payload must be an object" unless claims.is_a?(Hash)
          unless header["kid"].nil? || header["kid"].is_a?(String)
            raise AuthenticationError, "JWT signing key ID is invalid"
          end

          yield(header, claims)
        end
        payload
      rescue JWT::DecodeError => error
        raise AuthenticationError, "JWT validation failed: #{error.message}"
      end

      def unverified_claims(token)
        claims, = JWT.decode(token, nil, false)
        claims.is_a?(Hash) ? claims : {}
      rescue JWT::DecodeError => error
        raise AuthenticationError, "JWT validation failed: #{error.message}"
      end

      def entra_issuer?(issuer)
        return false unless issuer.is_a?(String)

        issuer.start_with?("#{@cloud.login_endpoint}/") || issuer.start_with?(ENTRA_V1_ISSUER_PREFIX)
      end

      def validate_entra_inbound!(token, claims)
        tenant_id = claims["tid"]
        raise AuthenticationError, "Entra inbound token is missing tid" if tenant_id.to_s.empty?

        issuers = ["#{@cloud.login_endpoint}/#{tenant_id}/v2.0", "#{ENTRA_V1_ISSUER_PREFIX}#{tenant_id}/"]
        # Cheap claim checks run first so junk inbound tokens cannot trigger
        # JWKS fetches for arbitrary tenants; decode! re-verifies both after
        # the signature.
        raise AuthenticationError, "JWT issuer is invalid" unless issuers.include?(claims["iss"])
        raise AuthenticationError, "JWT audience is invalid" if (Array(claims["aud"]) & valid_audiences).empty?

        uri = entra_tenant_jwks_uri(tenant_id)
        decode!(token, issuers: issuers) do |header, _decoded|
          signing_key(uri, header["kid"])
        end
      end

      # Inbound tokens may be audienced as the bare app id, api://{appId},
      # or api://botid-{appId}; all three SDKs accept all three forms.
      def valid_audiences
        [@client_id, "api://#{@client_id}", "api://botid-#{@client_id}"]
      end

      def validate_service_url!(payload, expected_service_url)
        token_service_url = payload["serviceurl"]
        raise AuthenticationError, "Token missing serviceurl claim" if token_service_url.to_s.empty?

        normalized_token_url = normalize_url(token_service_url)
        normalized_expected_url = normalize_url(expected_service_url)

        return if normalized_token_url == normalized_expected_url

        raise AuthenticationError, "Service URL mismatch. Token: #{normalized_token_url}, Expected: #{normalized_expected_url}"
      end

      def signing_key(uri, kid)
        unless kid.nil? || kid.is_a?(String)
          raise AuthenticationError, "JWT signing key ID is invalid"
        end

        @jwks_mutex.synchronize do
          provider = @jwks_loaders[uri]
          unless provider
            @jwks_loaders.shift while @jwks_loaders.length >= MAX_JWKS_ENDPOINTS
            provider = @jwks_loaders[uri] = JwkLoader.for_uri(
              uri:, cache: JwkLoader::MemoryCache.new, cache_max_age: JWKS_CACHE_MAX_AGE
            )
          end
          loader = lambda do |options|
            keys = provider.call(options).select do |key|
              key[:kty] == "RSA" && [nil, "sig"].include?(key[:use])
            end
            if kid.nil? && keys.size != 1
              raise AuthenticationError, "JWT signing key was not found"
            end

            JWT::JWK::Set.new(keys)
          end

          JWT::JWK::KeyFinder.new(jwks: loader, allow_nil_kid: true).key_for(kid)
        end
      rescue Net::HTTPExceptions, JSON::ParserError, Timeout::Error, SocketError, IOError, SystemCallError, ArgumentError,
             OpenSSL::SSL::SSLError, OpenSSL::PKey::PKeyError, OpenSSL::ASN1::ASN1Error => error
        raise AuthenticationError, "Unable to retrieve JWT signing key: #{error.message}"
      end

      def jwks_uri_for_issuer(issuer)
        raise AuthenticationError, "JWT issuer is invalid" unless valid_issuers.include?(issuer)

        issuer == @cloud.token_issuer ? bot_framework_jwks_uri : entra_tenant_jwks_uri(@tenant_id)
      end

      def bot_framework_jwks_uri
        @discovery_mutex.synchronize do
          @bot_framework_jwks_uri ||= begin
            metadata = @http.get(@cloud.open_id_metadata_url)
            unless metadata.is_a?(Hash) && metadata["jwks_uri"].is_a?(String) && !metadata["jwks_uri"].empty?
              raise AuthenticationError, "JWT signing keys metadata is invalid"
            end

            metadata["jwks_uri"]
          end
        end
      rescue HttpError, Faraday::Error => error
        raise AuthenticationError, "Unable to retrieve JWT signing keys metadata: #{error.message}"
      end

      def entra_tenant_jwks_uri(tenant_id)
        "#{@cloud.login_endpoint}/#{tenant_id}/discovery/v2.0/keys"
      end

      def valid_issuers
        issuers = [@cloud.token_issuer]
        if @tenant_id
          issuers.concat(["#{@cloud.login_endpoint}/#{@tenant_id}/v2.0", "#{ENTRA_V1_ISSUER_PREFIX}#{@tenant_id}/"])
        end

        issuers
      end

      def normalize_url(value)
        value.to_s.sub(%r{/+\z}, "").downcase
      end

    end
  end
end
