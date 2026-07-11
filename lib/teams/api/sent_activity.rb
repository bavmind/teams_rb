# frozen_string_literal: true

module Teams
  module Api
    # Represents an activity that was sent: the outbound activity merged with
    # the server response, so the server-assigned id is always available.
    # Mirrors the SDKs' SentActivity.
    class SentActivity
      attr_reader :raw

      def self.merge(activity, response)
        activity_hash = activity.respond_to?(:to_h) ? activity.to_h : activity
        activity_hash = {} unless activity_hash.is_a?(Hash)
        response_hash = response.is_a?(Hash) ? response : {}

        new(activity_hash.merge(response_hash))
      end

      def initialize(raw = {})
        @raw = raw
      end

      def id
        raw["id"] || raw[:id]
      end

      def type
        raw["type"]
      end

      def text
        raw["text"]
      end

      def conversation_id
        raw.dig("conversation", "id")
      end

      def [](key)
        raw[key]
      end

      def to_h
        raw.dup
      end
    end
  end
end
