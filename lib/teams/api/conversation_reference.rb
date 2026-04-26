# frozen_string_literal: true

require "json"

module Teams
  module Api
    class ConversationReference
      attr_reader :activity_id, :user, :locale, :bot, :conversation, :channel_id, :service_url

      def self.from_activity(activity)
        new(
          activity_id: activity.id,
          user: activity.from,
          locale: activity.locale,
          bot: activity.recipient,
          conversation: activity.conversation,
          channel_id: activity.channel_id,
          service_url: activity.service_url
        )
      end

      def self.from_h(raw)
        raw = raw.to_h if raw.respond_to?(:to_h)

        new(
          activity_id: raw["activityId"] || raw["activity_id"] || raw[:activityId] || raw[:activity_id],
          user: raw["user"] || raw[:user],
          locale: raw["locale"] || raw[:locale],
          bot: raw.fetch("bot") { raw.fetch(:bot) },
          conversation: raw.fetch("conversation") { raw.fetch(:conversation) },
          channel_id: raw["channelId"] || raw["channel_id"] || raw[:channelId] || raw[:channel_id],
          service_url: raw["serviceUrl"] || raw["service_url"] || raw[:serviceUrl] || raw[:service_url]
        )
      end

      def initialize(activity_id: nil, user: nil, locale: nil, bot:, conversation:, channel_id:, service_url:)
        @activity_id = activity_id
        @user = wrap_hash(user)
        @locale = locale
        @bot = wrap_hash(bot)
        @conversation = wrap_hash(conversation)
        @channel_id = channel_id
        @service_url = service_url
      end

      def conversation_id
        conversation.id
      end

      def to_h
        body = {
          "bot" => bot.to_h,
          "conversation" => conversation.to_h,
          "channelId" => channel_id,
          "serviceUrl" => service_url
        }
        body["activityId"] = activity_id if activity_id
        body["user"] = user.to_h if user
        body["locale"] = locale if locale
        body
      end

      def to_json(*args)
        JSON.generate(to_h, *args)
      end

      private

      def wrap_hash(value)
        return value if value.is_a?(HashObject)
        return nil if value.nil?

        HashObject.new(value)
      end
    end
  end
end
