# frozen_string_literal: true

require "json"

module Teams
  module State
    # Configuration for per-turn state: the backing storage (any object with
    # get/set/delete, like Teams::Storage::MemoryStore; defaults to the app's
    # storage) and the key namespace. Expiry and other storage behavior belong
    # to the storage provider.
    StateOptions = Struct.new(:storage, :key_prefix, keyword_init: true) do
      def initialize(storage: nil, key_prefix: "ts")
        super
      end
    end

    # Loads and persists TurnState scopes over the storage interface, like the
    # TypeScript, Python, and .NET loaders. Scopes are stored as JSON strings
    # under {prefix}:conv:{conversationId} and
    # {prefix}:user:{conversationId}:{userId}, with each id percent-encoded
    # so distinct ids can never share a key.
    class TurnStateLoader
      UNRESERVED = /[^A-Za-z0-9_.~-]/

      attr_reader :key_prefix

      def initialize(storage:, key_prefix: "ts", logger: nil)
        raise ArgumentError, "TurnStateLoader requires a storage backend" unless storage

        @storage = storage
        @key_prefix = key_prefix
        @logger = logger
      end

      def conversation_key(conversation_id)
        "#{key_prefix}:conv:#{encode_segment(conversation_id)}"
      end

      def user_key(conversation_id, user_id)
        "#{key_prefix}:user:#{encode_segment(conversation_id)}:#{encode_segment(user_id)}"
      end

      # Loads both scopes; user is nil when user_id is.
      def load(conversation_id, user_id = nil)
        conversation = load_scope(conversation_key(conversation_id))
        user = user_id ? load_scope(user_key(conversation_id, user_id)) : nil

        TurnStateContainer.new(
          conversation:,
          conversation_id:,
          user:,
          user_id:,
          deleter: -> { delete(conversation_id, user_id) },
          saver: method(:save)
        )
      end

      # Persists dirty scopes under the identity the container was loaded for;
      # dirty scopes that became empty are deleted. Every scope is serialized
      # before any storage write, so an unserializable value cannot leave
      # state half-saved, and scopes are marked clean only after all writes
      # succeed.
      def save(container)
        raise ArgumentError, "TurnStateContainer#conversation_id must be set to save state" if blank?(container.conversation_id)
        if container.user && blank?(container.user_id)
          raise ArgumentError, "TurnStateContainer#user_id must be set to save user state"
        end

        deletes = []
        sets = []
        clean = []
        prepare(conversation_key(container.conversation_id), container.conversation, deletes, sets, clean)
        if container.user
          prepare(user_key(container.conversation_id, container.user_id), container.user, deletes, sets, clean)
        end

        deletes.each { |key| @storage.delete(key) }
        sets.each { |key, value| @storage.set(key, value) }
        clean.each(&:mark_clean)
        nil
      end

      def delete(conversation_id, user_id = nil)
        @storage.delete(conversation_key(conversation_id))
        @storage.delete(user_key(conversation_id, user_id)) if user_id
        nil
      end

      private

      def prepare(key, scope, deletes, sets, clean)
        return unless scope.dirty?

        if scope.empty?
          deletes << key
        else
          sets << [key, JSON.generate(scope.to_h, strict: true)]
        end
        clean << scope
      end

      def load_scope(key)
        raw = @storage.get(key)
        return TurnState.new if raw.nil?

        data = deserialize(raw)
        unless data
          @storage.delete(key)
          return TurnState.new
        end

        TurnState.new(data)
      end

      # Never raises: unreadable or malformed blobs count as missing. Storage
      # providers that hand back already-parsed hashes are accepted.
      def deserialize(raw)
        parsed = case raw
        when Hash then raw
        when String
          begin
            JSON.parse(raw)
          rescue JSON::ParserError
            @logger&.debug("Discarding unreadable state blob at load")
            return nil
          end
        end
        return nil unless parsed.is_a?(Hash)
        return nil unless parsed.keys.all?(String)

        parsed
      end

      def encode_segment(value)
        value.to_s.b.gsub(UNRESERVED) { |byte| format("%%%02X", byte.ord) }
      end

      def blank?(value)
        value.nil? || value.to_s.empty?
      end
    end
  end
end
