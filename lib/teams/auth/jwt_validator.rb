# frozen_string_literal: true

require "base64"
require "json"
require "openssl"

module Teams
  module Auth
    class JwtValidator
      ENTRA_V1_ISSUER_PREFIX = "https://sts.windows.net/"
      # Bounded so random tenant ids in unverified inbound tokens cannot
      # grow the JWKS cache forever, like the TypeScript/Python validators.
      MAX_ENTRA_JWKS_CACHE_SIZE = 100

      def initialize(client_id:, tenant_id: nil, cloud: PUBLIC_CLOUD, http: nil)
        @client_id = client_id
        @tenant_id = tenant_id
        @cloud = cloud
        @http = http || Common::HttpClient.new
        @jwks = {}
        @entra_jwks = {}
        # The validator is shared across request threads; the mutex keeps
        # concurrent cold-cache requests from fetching the JWKS repeatedly.
        @jwks_mutex = Mutex.new
      end

      def validate!(authorization_header, service_url: nil)
        header, payload, signing_input, signature = decode_bearer(authorization_header)
        validate_claims!(payload)
        validate_service_url!(payload, service_url) if service_url
        verify_signature!(header, signing_input, signature, jwks_for_issuer(payload["iss"]))
        payload
      end

      # Validates an inbound activity token. Classic bot activities carry
      # Bot Framework service tokens and validate exactly like validate!;
      # Agent 365 activities carry Entra tokens audienced to the agentic app
      # blueprint, validated against the token's own tenant. The Entra path
      # skips the serviceurl claim: agentic inbound tokens do not carry it
      # (upstream revisits once the platform defines a signed equivalent).
      def validate_inbound_activity!(authorization_header, service_url: nil)
        header, payload, signing_input, signature = decode_bearer(authorization_header)
        return validate_entra_inbound!(header, payload, signing_input, signature) if entra_issuer?(payload["iss"])

        validate_claims!(payload)
        validate_service_url!(payload, service_url) if service_url
        verify_signature!(header, signing_input, signature, jwks_for_issuer(payload["iss"]))
        payload
      end

      private

      def decode_bearer(authorization_header)
        raise AuthenticationError, "Authorization header is required" if authorization_header.to_s.empty?

        scheme, token = authorization_header.split(" ", 2)
        raise AuthenticationError, "Authorization must be Bearer" unless scheme&.casecmp("Bearer")&.zero? && token

        decode(token)
      end

      def entra_issuer?(issuer)
        return false unless issuer.is_a?(String)

        issuer.start_with?("#{@cloud.login_endpoint}/") || issuer.start_with?(ENTRA_V1_ISSUER_PREFIX)
      end

      def validate_entra_inbound!(header, payload, signing_input, signature)
        tenant_id = payload["tid"]
        raise AuthenticationError, "Entra inbound token is missing tid" if tenant_id.to_s.empty?

        now = Time.now.to_i
        raise AuthenticationError, "JWT expired" if payload["exp"] && now >= payload["exp"].to_i
        raise AuthenticationError, "JWT not active yet" if payload["nbf"] && now < payload["nbf"].to_i

        valid_issuers = ["#{@cloud.login_endpoint}/#{tenant_id}/v2.0", "#{ENTRA_V1_ISSUER_PREFIX}#{tenant_id}/"]
        raise AuthenticationError, "JWT issuer is invalid" unless valid_issuers.include?(payload["iss"])
        raise AuthenticationError, "JWT audience is invalid" if (Array(payload["aud"]) & valid_audiences).empty?

        verify_signature!(header, signing_input, signature, entra_tenant_jwks(tenant_id))
        payload
      end

      def entra_tenant_jwks(tenant_id)
        uri = "#{@cloud.login_endpoint}/#{tenant_id}/discovery/v2.0/keys"
        @jwks_mutex.synchronize do
          jwks = (@entra_jwks[uri] ||= @http.get(uri))
          @entra_jwks.shift while @entra_jwks.length > MAX_ENTRA_JWKS_CACHE_SIZE
          jwks
        end
      end

      def decode(token)
        header_segment, payload_segment, signature_segment = token.split(".")
        raise AuthenticationError, "JWT must contain three segments" unless signature_segment

        header = JSON.parse(Base64.urlsafe_decode64(pad(header_segment)))
        payload = JSON.parse(Base64.urlsafe_decode64(pad(payload_segment)))
        signature = Base64.urlsafe_decode64(pad(signature_segment))
        [header, payload, "#{header_segment}.#{payload_segment}", signature]
      rescue JSON::ParserError, ArgumentError
        raise AuthenticationError, "JWT is malformed"
      end

      def validate_claims!(payload)
        now = Time.now.to_i
        raise AuthenticationError, "JWT expired" if payload["exp"] && now >= payload["exp"].to_i
        raise AuthenticationError, "JWT not active yet" if payload["nbf"] && now < payload["nbf"].to_i
        raise AuthenticationError, "JWT issuer is invalid" unless valid_issuer?(payload["iss"])
        raise AuthenticationError, "JWT audience is invalid" if (Array(payload["aud"]) & valid_audiences).empty?
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

      def verify_signature!(header, signing_input, signature, jwks)
        raise AuthenticationError, "only RS256 JWTs are supported" unless header["alg"] == "RS256"

        key = jwks.fetch("keys").find { |candidate| candidate["kid"] == header["kid"] }
        raise AuthenticationError, "JWT signing key was not found" unless key

        public_key = rsa_public_key(key)
        unless public_key.verify(OpenSSL::Digest.new("SHA256"), signature, signing_input)
          raise AuthenticationError, "JWT signature is invalid"
        end
      end

      def jwks_for_issuer(issuer)
        uri = jwks_uri_for_issuer(issuer)

        @jwks_mutex.synchronize { @jwks[uri] ||= @http.get(uri) }
      end

      def jwks_uri_for_issuer(issuer)
        return bot_framework_jwks_uri if issuer == @cloud.token_issuer
        return entra_jwks_uri if @tenant_id && tenant_issuer?(issuer)

        bot_framework_jwks_uri
      end

      def bot_framework_jwks_uri
        @jwks_mutex.synchronize do
          @bot_framework_jwks_uri ||= begin
            metadata = @http.get(@cloud.open_id_metadata_url)
            metadata.fetch("jwks_uri")
          end
        end
      end

      def entra_jwks_uri
        "#{@cloud.login_endpoint}/#{@tenant_id}/discovery/v2.0/keys"
      end

      def valid_issuer?(issuer)
        return true if issuer == @cloud.token_issuer
        return false unless @tenant_id

        tenant_issuer?(issuer)
      end

      def tenant_issuer?(issuer)
        issuer == "#{@cloud.login_endpoint}/#{@tenant_id}/v2.0" ||
          issuer == "https://sts.windows.net/#{@tenant_id}/"
      end

      def normalize_url(value)
        value.to_s.sub(%r{/+\z}, "").downcase
      end

      def rsa_public_key(jwk)
        n = OpenSSL::BN.new(Base64.urlsafe_decode64(pad(jwk.fetch("n"))), 2)
        e = OpenSSL::BN.new(Base64.urlsafe_decode64(pad(jwk.fetch("e"))), 2)

        sequence = OpenSSL::ASN1::Sequence([
          OpenSSL::ASN1::Integer(n),
          OpenSSL::ASN1::Integer(e)
        ])
        OpenSSL::PKey::RSA.new(sequence.to_der)
      end

      def pad(segment)
        segment + ("=" * ((4 - segment.length % 4) % 4))
      end
    end
  end
end
