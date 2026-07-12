# frozen_string_literal: true

module Teams
  module Storage
    class MemoryStore
      def initialize(initial = {})
        @data = initial.dup
        # The store is shared across request threads in multi-threaded Rack
        # servers. The upstream SDKs run single-threaded event loops and can
        # skip locking; Ruby cannot.
        @mutex = Mutex.new
      end

      def get(key)
        @mutex.synchronize { @data[key] }
      end

      def set(key, value)
        @mutex.synchronize { @data[key] = value }
      end

      def delete(key)
        @mutex.synchronize { @data.delete(key) }
      end
    end
  end
end
