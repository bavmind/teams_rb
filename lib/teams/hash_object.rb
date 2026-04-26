# frozen_string_literal: true

module Teams
  class HashObject
    attr_reader :raw

    def initialize(raw = {})
      @raw = raw || {}
    end

    def [](key)
      fetch_value(key)
    end

    def to_h
      raw
    end

    def method_missing(name, ...)
      key = name.to_s
      value = fetch_value(key)
      return wrap(value) unless value.nil?

      super
    end

    def respond_to_missing?(name, include_private = false)
      has_key?(name.to_s) || super
    end

    private

    def has_key?(key)
      raw.key?(key) || raw.key?(camelize(key)) || raw.key?(key.to_sym)
    end

    def fetch_value(key)
      raw[key] || raw[camelize(key)] || raw[key.to_sym]
    end

    def camelize(key)
      parts = key.to_s.split("_")
      parts.first + parts.drop(1).map(&:capitalize).join
    end

    def wrap(value)
      case value
      when Hash
        HashObject.new(value)
      when Array
        value.map { |item| item.is_a?(Hash) ? HashObject.new(item) : item }
      else
        value
      end
    end
  end
end
