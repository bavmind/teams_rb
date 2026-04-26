# frozen_string_literal: true

module Teams
  module Storage
    class MemoryStore
      def initialize(initial = {})
        @data = initial.dup
      end

      def get(key)
        @data[key]
      end

      def set(key, value)
        @data[key] = value
      end

      def delete(key)
        @data.delete(key)
      end
    end
  end
end
