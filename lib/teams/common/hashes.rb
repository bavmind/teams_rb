# frozen_string_literal: true

module Teams
  module Common
    module Hashes
      module_function

      def deep_stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, item), hash| hash[key.to_s] = deep_stringify_keys(item) }
        when Array
          value.map { |item| deep_stringify_keys(item) }
        else
          value
        end
      end
    end
  end
end
