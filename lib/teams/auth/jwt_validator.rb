# frozen_string_literal: true

require "base64"
require "json"
require "openssl"

module Teams
  module Auth
    class JwtValidator
      def initialize(client_id:, cloud: PUBLIC_CLOUD, http: nil)
        @client_id = client_id
        @cloud = cloud
        @http = http || Common::HttpClient.new
      end

      def validate!(authorization_header)
        raise AuthenticationError, "Authorization header is required" if authorization_header.to_s.empty?

        scheme, token = authorization_header.split(" ", 2)
        raise AuthenticationError, "Authorization must be Bearer" unless scheme&.casecmp("Bearer")&.zero? && token

        header, payload, signing_input, signature = decode(token)
        validate_claims!(payload)
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
        raise AuthenticationError, "JWT issuer is invalid" unless payload["iss"] == @cloud.token_issuer
        raise AuthenticationError, "JWT audience is invalid" unless Array(payload["aud"]).include?(@client_id)
      end

      def verify_signature!(header, signing_input, signature)
        raise AuthenticationError, "only RS256 JWTs are supported" unless header["alg"] == "RS256"

        key = jwks.fetch("keys").find { |candidate| candidate["kid"] == header["kid"] }
        raise AuthenticationError, "JWT signing key was not found" unless key

        public_key = rsa_public_key(key)
        unless public_key.verify(OpenSSL::Digest.new("SHA256"), signature, signing_input)
          raise AuthenticationError, "JWT signature is invalid"
        end
      end

      def jwks
        @jwks ||= begin
          metadata = @http.get(@cloud.open_id_metadata_url)
          @http.get(metadata.fetch("jwks_uri"))
        end
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
