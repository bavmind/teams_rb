# frozen_string_literal: true

require "json"
require_relative "cards/generated_base"

module Teams
  module Cards
    class CardObject
      attr_reader :options

      def initialize(**options)
        @options = options
      end

      def to_h
        compact_hash(serialize_options(options))
      end

      def to_json(*args)
        JSON.generate(to_h, *args)
      end

      def with_options(options = nil, **kwargs)
        options = (options || {}).merge(kwargs)
        options.each { |key, value| with_option(key, value) }
        self
      end

      private

      def with_option(key, value)
        options[key] = value
        self
      end

      def serialize(value)
        case value
        when nil
          nil
        when Array
          value.map { |item| serialize(item) }
        when Hash
          serialize_options(value)
        else
          value.respond_to?(:to_h) ? value.to_h : value
        end
      end

      def serialize_options(values)
        values.each_with_object({}) do |(key, value), hash|
          hash[json_key(key)] = serialize(value)
        end
      end

      def compact_hash(hash)
        hash.reject { |_key, value| value.nil? }
      end

      def json_key(key)
        return key if key.is_a?(String)

        case key
        when :schema
          "$schema"
        when :choices_data
          "choices.data"
        when :grid_area
          "grid.area"
        else
          camelize(key)
        end
      end

      def camelize(key)
        parts = key.to_s.split("_")
        parts.first + parts.drop(1).map(&:capitalize).join
      end
    end

  end
end
