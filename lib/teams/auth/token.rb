# frozen_string_literal: true

require "base64"
require "json"

module Teams
  module Auth
    class Token
      attr_reader :value, :payload

      def initialize(value)
        @value = value
        @payload = decode_payload(value)
      end

      def expired?(skew: 60)
        exp = payload["exp"]
        return false unless exp

        Time.now.to_i >= exp.to_i - skew
      end

      private

      def decode_payload(value)
        _header, payload, = value.to_s.split(".")
        return {} unless payload

        JSON.parse(Base64.urlsafe_decode64(pad(payload)))
      rescue JSON::ParserError, ArgumentError
        {}
      end

      def pad(segment)
        segment + ("=" * ((4 - segment.length % 4) % 4))
      end
    end
  end
end
