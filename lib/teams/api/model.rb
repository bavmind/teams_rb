# frozen_string_literal: true

module Teams
  module Api
    class Model
      attr_reader :raw

      def initialize(raw = {})
        @raw = normalize_hash(raw)
      end

      def to_h
        raw.dup
      end

      private

      def read(*keys)
        keys.each do |key|
          return raw[key] if raw.key?(key)
          return raw[key.to_s] if raw.key?(key.to_s)
          return raw[key.to_sym] if raw.key?(key.to_sym)
        end

        nil
      end

      def normalize_hash(value)
        value = value.to_h if value.respond_to?(:to_h)
        return {} if value.nil?

        value.each_with_object({}) do |(key, item), result|
          result[key.to_s] = normalize_value(item)
        end
      end

      def normalize_value(value)
        case value
        when Hash
          normalize_hash(value)
        when Array
          value.map { |item| normalize_value(item) }
        else
          value
        end
      end
    end
  end
end
