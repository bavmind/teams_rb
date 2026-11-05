# frozen_string_literal: true

require "digest"
require "json"

module Teams
  module State
    # Raised when a sealed TurnState is used after its turn ended.
    class TurnStateSealedError < Teams::Error; end

    # One state scope (conversation or user) for a single turn. Behaves like a
    # Hash, mirroring Python's mapping-shaped TurnState, and adds what the
    # loader relies on:
    #
    # - Dirty tracking: contents are compared to the loaded snapshot, so nested
    #   mutations persist without reassignment and reverted changes write
    #   nothing.
    # - Sealing: at the end of the turn the scope is sealed and any later
    #   access raises TurnStateSealedError.
    #
    # Values must be JSON-serializable (String, Integer, Float, true/false,
    # nil, Array, Hash); a scope is saved as JSON at the end of the turn, so a
    # non-JSON value raises then. Keys are strings: a symbol key is read and
    # written as its string, and nested hash keys come back as strings after a
    # save.
    class TurnState
      include Enumerable

      def initialize(data = nil)
        @data = (data || {}).to_h.transform_keys(&:to_s)
        @baseline = fingerprint
        @sealed = false
      end

      def dirty?
        current = fingerprint
        current.nil? || current != @baseline
      end

      def empty?
        @data.empty?
      end

      def size
        @data.size
      end
      alias length size

      def sealed?
        @sealed
      end

      def seal
        @sealed = true
        self
      end

      # Forces the next save to write this scope.
      def mark_dirty
        @baseline = nil
        self
      end

      # Marks the current contents as saved; used by the loader.
      def mark_clean
        current = fingerprint
        @baseline = current if current
        self
      end

      def [](key)
        ensure_active!
        @data[key.to_s]
      end

      def []=(key, value)
        ensure_active!
        @data[key.to_s] = value
      end

      def fetch(key, *default, &block)
        ensure_active!
        @data.fetch(key.to_s, *default, &block)
      end

      def delete(key)
        ensure_active!
        @data.delete(key.to_s)
      end

      def key?(key)
        ensure_active!
        @data.key?(key.to_s)
      end
      alias include? key?
      alias has_key? key?
      alias member? key?

      def keys
        ensure_active!
        @data.keys
      end

      def values
        ensure_active!
        @data.values
      end

      # Iterates over a snapshot, so the scope can be changed while iterating.
      def each(&block)
        ensure_active!
        return enum_for(:each) unless block

        @data.to_a.each(&block)
        self
      end
      alias each_pair each

      def clear
        ensure_active!
        @data.clear
        self
      end

      # A shallow copy of the contents, for serialization. Does not check the
      # seal: the loader serializes a scope just before sealing it.
      def to_h
        @data.dup
      end

      def inspect
        status = if sealed?
          "sealed"
        else
          dirty? ? "dirty" : "clean"
        end
        "#<#{self.class.name} #{@data.inspect} (#{status})>"
      end

      private

      def ensure_active!
        raise TurnStateSealedError, "TurnState has been sealed and can no longer be accessed." if @sealed
      end

      # Canonical JSON (sorted keys) digest; nil when the contents cannot be
      # encoded, which counts as dirty.
      def fingerprint
        Digest::SHA256.hexdigest(JSON.generate(canonical(@data)))
      rescue JSON::GeneratorError, EncodingError
        nil
      end

      def canonical(value)
        case value
        when Hash then value.map { |key, item| [key.to_s, canonical(item)] }.sort_by(&:first).to_h
        when Array then value.map { |item| canonical(item) }
        else value
        end
      end
    end
  end
end
