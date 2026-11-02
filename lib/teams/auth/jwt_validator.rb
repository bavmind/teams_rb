# frozen_string_literal: true

require "jwt"

module Teams
  module Auth
    class JwtValidator
      JWKS_CACHE_TTL = 10 * 60
      JWKS_CACHE_MAX_ENTRIES = 5
      CLOCK_TOLERANCE = 5 * 60

      def initialize(client_id:, tenant_id: nil, cloud: PUBLIC_CLOUD, http: nil)
        @client_id = client_id
        @tenant_id = tenant_id
        @cloud = cloud
        @http = http || Common::HttpClient.new
        @jwks = {}
        @jwks_mutex = Mutex.new
        # Coordinate misses per endpoint without blocking cached-key reads.
        @jwks_fetch_mutexes = {}
        @discovery_mutex = Mutex.new
      end

      def validate!(authorization_header, service_url: nil)
        raise AuthenticationError, "Authorization header is required" if authorization_header.to_s.empty?

        scheme, token = authorization_header.split(" ", 2)
        raise AuthenticationError, "Authorization must be Bearer" unless scheme&.casecmp("Bearer")&.zero? && token

        payload, = JWT.decode(
          token, nil, true,
          algorithms: ["RS256"], leeway: CLOCK_TOLERANCE,
          verify_expiration: true, verify_not_before: true,
          verify_iss: true, iss: valid_issuers,
          verify_aud: true, aud: valid_audiences
        ) do |header, claims|
          raise AuthenticationError, "JWT payload must be an object" unless claims.is_a?(Hash)

          signing_key(claims["iss"], header["kid"])
        end
        validate_service_url!(payload, service_url) if service_url
        payload
      rescue JWT::DecodeError => error
        raise AuthenticationError, "JWT validation failed: #{error.message}"
      end

      private

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

      def signing_key(issuer, kid)
        unless kid.nil? || kid.is_a?(String)
          raise AuthenticationError, "JWT signing key ID is invalid"
        end

        uri = jwks_uri_for_issuer(issuer)
        cached = cached_signing_key(uri, kid)
        return cached if cached

        fetch_mutex = @jwks_mutex.synchronize { @jwks_fetch_mutexes[uri] ||= Mutex.new }
        fetch_mutex.synchronize do
          cached = cached_signing_key(uri, kid)
          return cached if cached

          key = fetch_signing_key(uri, kid)
          @jwks_mutex.synchronize do
            cache = @jwks[uri]
            cache.shift if cache.size >= JWKS_CACHE_MAX_ENTRIES
            cache[kid] = { key:, expires_at: monotonic_time + JWKS_CACHE_TTL }
          end
          key
        end
      end

      def cached_signing_key(uri, kid)
        @jwks_mutex.synchronize do
          cache = @jwks[uri] ||= {}
          cached = cache.delete(kid)
          if cached && monotonic_time < cached[:expires_at]
            cache[kid] = cached
            cached[:key]
          end
        end
      end

      def fetch_signing_key(uri, kid)
        document = @http.get(uri)
        unless document.is_a?(Hash) && document["keys"].is_a?(Array)
          raise AuthenticationError, "JWT signing keys response is invalid"
        end

        keys = document["keys"].select do |key|
          key.is_a?(Hash) && key["kty"] == "RSA" && [nil, "sig"].include?(key["use"])
        end
        if kid.nil? && keys.size != 1
          raise AuthenticationError, "JWT signing key was not found"
        end
        key = kid.nil? ? keys.first : keys.find { |candidate| candidate["kid"] == kid }
        raise AuthenticationError, "JWT signing key was not found" unless key

        unless [key["n"], key["e"]].all? { |value| value.is_a?(String) && !value.empty? }
          raise AuthenticationError, "JWT signing key is invalid"
        end

        JWT::JWK.import(key).verify_key
      rescue HttpError, Faraday::Error, JWT::DecodeError, ArgumentError, OpenSSL::PKey::PKeyError, OpenSSL::ASN1::ASN1Error => error
        raise AuthenticationError, "Unable to retrieve JWT signing key: #{error.message}"
      end

      def jwks_uri_for_issuer(issuer)
        raise AuthenticationError, "JWT issuer is invalid" unless valid_issuers.include?(issuer)

        issuer == @cloud.token_issuer ? bot_framework_jwks_uri : entra_jwks_uri
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

      def entra_jwks_uri
        "#{@cloud.login_endpoint}/#{@tenant_id}/discovery/v2.0/keys"
      end

      def valid_issuers
        issuers = [@cloud.token_issuer]
        if @tenant_id
          issuers.concat(["#{@cloud.login_endpoint}/#{@tenant_id}/v2.0", "https://sts.windows.net/#{@tenant_id}/"])
        end

        issuers
      end

      def normalize_url(value)
        value.to_s.sub(%r{/+\z}, "").downcase
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
