# frozen_string_literal: true

require "base64"
require "json"
require "openssl"

module Teams
  module Auth
    class JwtValidator
      def initialize(client_id:, tenant_id: nil, cloud: PUBLIC_CLOUD, http: nil)
        @client_id = client_id
        @tenant_id = tenant_id
        @cloud = cloud
        @http = http || Common::HttpClient.new
        @jwks = {}
      end

      def validate!(authorization_header, service_url: nil)
        raise AuthenticationError, "Authorization header is required" if authorization_header.to_s.empty?

        scheme, token = authorization_header.split(" ", 2)
        raise AuthenticationError, "Authorization must be Bearer" unless scheme&.casecmp("Bearer")&.zero? && token

        header, payload, signing_input, signature = decode(token)
        validate_claims!(payload)
        validate_service_url!(payload, service_url) if service_url
        verify_signature!(header, signing_input, signature)
        payload
      end

      private

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

      def verify_signature!(header, signing_input, signature)
        raise AuthenticationError, "only RS256 JWTs are supported" unless header["alg"] == "RS256"

        key = jwks_for_issuer(signing_input).fetch("keys").find { |candidate| candidate["kid"] == header["kid"] }
        raise AuthenticationError, "JWT signing key was not found" unless key

        public_key = rsa_public_key(key)
        unless public_key.verify(OpenSSL::Digest.new("SHA256"), signature, signing_input)
          raise AuthenticationError, "JWT signature is invalid"
        end
      end

      def jwks_for_issuer(signing_input)
        _header_segment, payload_segment = signing_input.split(".", 2)
        payload = JSON.parse(Base64.urlsafe_decode64(pad(payload_segment)))
        uri = jwks_uri_for_issuer(payload["iss"])

        @jwks[uri] ||= @http.get(uri)
      rescue JSON::ParserError, ArgumentError
        raise AuthenticationError, "JWT is malformed"
      end

      def jwks_uri_for_issuer(issuer)
        return bot_framework_jwks_uri if issuer == @cloud.token_issuer
        return entra_jwks_uri if @tenant_id && tenant_issuer?(issuer)

        bot_framework_jwks_uri
      end

      def bot_framework_jwks_uri
        @bot_framework_jwks_uri ||= begin
          metadata = @http.get(@cloud.open_id_metadata_url)
          metadata.fetch("jwks_uri")
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
