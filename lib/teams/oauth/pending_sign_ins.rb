# frozen_string_literal: true

require "time"

module Teams
  module OAuth
    # A sign-in awaiting its callback: the connection it started on, when,
    # and whether the card offered silent SSO (a token exchange resource).
    PendingSignIn = Struct.new(:connection_name, :created_at, :sso_offered, keyword_init: true)

    # Timestamps shared by the pending and exchange markers: ISO 8601 UTC,
    # readable across the SDKs (a value without an offset is read as UTC).
    module Timestamps
      module_function

      def format(epoch_seconds)
        Time.at(epoch_seconds).utc.iso8601(6)
      end

      def parse(raw)
        return nil unless raw.is_a?(String)

        value = raw.match?(/(z|[+-]\d{2}:?\d{2})\z/i) ? raw : "#{raw}Z"
        Time.iso8601(value).to_f
      rescue ArgumentError
        nil
      end
    end

    # Process-local pending sign-ins, used when per-turn state is off. Bounded
    # and short-lived; a callback handled by another process cannot be
    # attributed from here.
    class LocalPendingCache
      TTL = 300.0
      MAX_ENTRIES = 1000

      def initialize
        @entries = {}
        @mutex = Mutex.new
      end

      def record(conversation_id, user_id, connection_name, sso_offered:)
        key = cache_key(conversation_id, user_id, connection_name)
        return unless key

        @mutex.synchronize do
          now = Time.now.to_f
          prune(now)
          @entries.delete(key)
          @entries[key] = PendingSignIn.new(connection_name: connection_name.strip, created_at: now, sso_offered:)
          @entries.shift while @entries.size > MAX_ENTRIES
        end
      end

      # Unexpired hints for this conversation and user, newest first.
      def entries(conversation_id, user_id)
        return [] if blank?(conversation_id) || blank?(user_id)

        found = @mutex.synchronize do
          prune(Time.now.to_f)
          @entries.select { |(conv, user, _), _| conv == conversation_id && user == user_id }.values
        end
        PendingSignIns.sort(found)
      end

      def clear(conversation_id, user_id, connection_name = nil)
        return if blank?(conversation_id) || blank?(user_id)

        target = connection_name.nil? ? nil : OAuth.lookup_key(connection_name)
        return if connection_name && target.nil?

        @mutex.synchronize do
          @entries.delete_if do |(conv, user, connection), _|
            conv == conversation_id && user == user_id && (target.nil? || connection == target)
          end
        end
      end

      # Restores an exact prior set of hints, keeping their timestamps.
      def replace(conversation_id, user_id, pending)
        return if blank?(conversation_id) || blank?(user_id)

        clear(conversation_id, user_id)
        @mutex.synchronize do
          pending.each do |hint|
            key = cache_key(conversation_id, user_id, hint.connection_name)
            @entries[key] = hint.dup.tap { |entry| entry.connection_name = hint.connection_name.strip } if key
          end
        end
      end

      private

      def cache_key(conversation_id, user_id, connection_name)
        return nil if blank?(conversation_id) || blank?(user_id)

        connection = OAuth.lookup_key(connection_name)
        connection ? [conversation_id, user_id, connection] : nil
      end

      def prune(now)
        @entries.delete_if { |_, entry| now - entry.created_at >= TTL }
      end

      def blank?(value)
        value.nil? || value.to_s.empty?
      end
    end

    # Pending sign-ins are recorded in the user state scope when per-turn
    # state is available ("__oauth:pending:{connection}" plus an
    # "__oauth:pending:sso:{connection}" marker when silent SSO was offered),
    # and in the process-local cache otherwise. Same keys and lifetimes as
    # the Python SDK.
    module PendingSignIns
      KEY_PREFIX = "__oauth:pending:"
      SSO_INFIX = "sso:"
      MAX_AGE = 5 * 60
      MAX_CLOCK_SKEW = 60

      module_function

      def record(state, local, connection_name, sso_offered:, conversation_id:, user_id:)
        user = state&.user
        return local.record(conversation_id, user_id, connection_name, sso_offered:) unless user

        read_markers(user)
        remove_connection(user, connection_name)
        stamp = Timestamps.format(Time.now.to_f)
        user[pending_key(connection_name)] = stamp
        user[sso_key(connection_name)] = stamp if sso_offered
      end

      # Live pending sign-ins, newest first.
      def list(state, local, conversation_id:, user_id:)
        user = state&.user
        return local.entries(conversation_id, user_id) unless user

        sort(read_markers(user).values)
      end

      # Clears one connection's hint, or every hint when connection_name is nil.
      def clear(state, local, connection_name = nil, conversation_id:, user_id:)
        user = state&.user
        return local.clear(conversation_id, user_id, connection_name) unless user

        if connection_name.nil?
          user.keys.each { |key| user.delete(key) if key.start_with?(KEY_PREFIX) }
        else
          remove_connection(user, connection_name)
        end
      end

      def replace(state, local, pending, conversation_id:, user_id:)
        user = state&.user
        return local.replace(conversation_id, user_id, pending) unless user

        clear(state, local, conversation_id:, user_id:)
        pending.each do |hint|
          stamp = Timestamps.format(hint.created_at)
          user[pending_key(hint.connection_name)] = stamp
          user[sso_key(hint.connection_name)] = stamp if hint.sso_offered
        end
      end

      def sort(pending)
        pending.sort_by { |hint| [-hint.created_at, hint.connection_name.downcase] }
      end

      def pending_key(connection_name)
        "#{KEY_PREFIX}#{connection_name.strip}"
      end

      def sso_key(connection_name)
        "#{KEY_PREFIX}#{SSO_INFIX}#{connection_name.strip}"
      end

      # [key, connection_name, sso_marker?] for every pending marker. "sso:"
      # can start a real connection name, so "__oauth:pending:sso:x" is x's
      # SSO marker only while x's own marker exists.
      def markers(user)
        keys = user.keys.select { |key| key.start_with?(KEY_PREFIX) }
        keys.map do |key|
          name = key.delete_prefix(KEY_PREFIX)
          if name.start_with?(SSO_INFIX)
            owner = name.delete_prefix(SSO_INFIX)
            next [key, owner, true] if keys.include?(pending_key(owner))
          end
          [key, name, false]
        end
      end

      # Parses live markers into hints keyed by lowercased connection name,
      # dropping malformed, future-dated, and expired markers from state.
      def read_markers(user)
        now = Time.now.to_f
        hints = {}
        sso_owners = {}
        markers(user).each do |key, name, sso_marker|
          next unless user.key?(key)

          created_at = Timestamps.parse(user[key])
          if created_at.nil? || created_at - now > MAX_CLOCK_SKEW || now - created_at > MAX_AGE
            user.delete(key)
            next
          end
          if sso_marker
            sso_owners[name.downcase] = name
            next
          end

          candidate = PendingSignIn.new(connection_name: name, created_at:, sso_offered: false)
          existing = hints[name.downcase]
          if existing
            loser, winner = candidate.created_at >= existing.created_at ? [existing, candidate] : [candidate, existing]
            user.delete(pending_key(loser.connection_name))
            user.delete(sso_key(loser.connection_name))
            candidate = winner
          end
          hints[name.downcase] = candidate
        end
        sso_owners.each { |lowered, owner| user.delete(sso_key(owner)) unless hints.key?(lowered) }
        hints.each { |lowered, hint| hint.sso_offered = sso_owners.key?(lowered) }
        hints
      end

      def remove_connection(user, connection_name)
        target = OAuth.lookup_key(connection_name)
        markers(user).each { |key, name, _| user.delete(key) if OAuth.lookup_key(name) == target }
      end
    end

    # Completed token exchanges, recorded in conversation state so a
    # duplicate routed to another instance still short-circuits (best-effort:
    # storage has no compare-and-set, so the in-process guard is what makes
    # same-instance dedup atomic, as in the other SDKs).
    module ExchangeMarkers
      KEY_PREFIX = "__oauth:exchange:"
      TTL = 5 * 60
      MAX_ENTRIES = 1000

      module_function

      def key(exchange_id)
        "#{KEY_PREFIX}#{exchange_id}"
      end

      def completed?(state, exchange_id)
        return false if state.nil? || exchange_id.to_s.empty?

        raw = state.conversation[key(exchange_id)]
        return false if raw.nil?

        completed_at = parse(raw)
        if completed_at.nil? || Time.now.to_f - completed_at > TTL
          state.conversation.delete(key(exchange_id))
          return false
        end
        true
      end

      # Never cleared when the exchange finishes, so a late duplicate from a
      # second Teams endpoint still deduplicates; markers age out after TTL,
      # and the oldest are trimmed past MAX_ENTRIES (never the new one).
      def record(state, exchange_id)
        return if state.nil? || exchange_id.to_s.empty?

        conversation = state.conversation
        now = Time.now.to_f
        conversation.keys.each do |stored|
          next unless stored.start_with?(KEY_PREFIX)

          completed_at = parse(conversation[stored])
          conversation.delete(stored) if completed_at.nil? || now - completed_at > TTL
        end
        written = key(exchange_id)
        conversation[written] = Timestamps.format(now)

        stored_keys = conversation.keys.select { |stored| stored.start_with?(KEY_PREFIX) }
        overflow = stored_keys.size - MAX_ENTRIES
        return unless overflow.positive?

        stored_keys.sort_by { |stored| [parse(conversation[stored]) || -Float::INFINITY, stored] }.each do |stored|
          break unless overflow.positive?
          next if stored == written

          conversation.delete(stored)
          overflow -= 1
        end
      end

      def parse(raw)
        completed_at = Timestamps.parse(raw)
        return nil if completed_at.nil? || completed_at > Time.now.to_f + PendingSignIns::MAX_CLOCK_SKEW

        completed_at
      end
    end
  end
end
