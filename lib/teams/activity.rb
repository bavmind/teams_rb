# frozen_string_literal: true

module Teams
  class Activity
    attr_reader :raw

    def initialize(raw = {})
      @raw = normalize_hash(raw)
    end

    def type
      raw["type"]
    end

    def name
      raw["name"]
    end

    def text
      raw["text"]
    end

    def id
      raw["id"]
    end

    def reply_to_id
      raw["replyToId"] || raw["reply_to_id"]
    end

    def service_url
      raw["serviceUrl"] || raw["service_url"]
    end

    def channel_id
      raw["channelId"] || raw["channel_id"]
    end

    def locale
      raw["locale"]
    end

    def local_timestamp
      raw["localTimestamp"] || raw["local_timestamp"]
    end

    def channel_data
      Api::ChannelData.new(raw["channelData"] || raw["channel_data"] || {})
    end

    def from
      Api::Account.new(raw["from"] || {})
    end

    def recipient
      Api::Account.new(raw["recipient"] || {})
    end

    def conversation
      Api::ConversationAccount.new(raw["conversation"] || {})
    end

    def value
      value = raw["value"]
      value.is_a?(Hash) ? Api::ActivityValue.new(value) : value
    end

    def entities
      Array(raw["entities"])
    end

    def get_quoted_messages
      entities
        .select { |entity| entity.is_a?(Hash) && entity["type"] == "quotedReply" }
        .map { |entity| Api::QuotedReplyEntity.new(entity) }
    end

    def to_h
      raw.dup
    end

    def message?
      type == "message"
    end

    def typing?
      type == "typing"
    end

    def invoke?
      type == "invoke"
    end

    def install_update?
      type == "installationUpdate"
    end

    def suggested_action_submit?
      type == "invoke" && name == "suggestedActions/submit"
    end

    private

    def normalize_hash(value)
      return {} if value.nil?

      value.each_with_object({}) do |(key, item), result|
        result[key.to_s] = normalize_value(item)
      end
    end

    def normalize_value(value)
      case value
      when Hash
        normalize_hash(value)
      when Array
        value.map { |item| normalize_value(item) }
      else
        value
      end
    end
  end
end
