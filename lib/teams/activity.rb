# frozen_string_literal: true

module Teams
  class Activity < HashObject
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

    def from
      HashObject.new(raw["from"] || {})
    end

    def recipient
      HashObject.new(raw["recipient"] || {})
    end

    def conversation
      HashObject.new(raw["conversation"] || {})
    end

    def value
      value = raw["value"]
      value.is_a?(Hash) ? HashObject.new(value) : value
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
  end
end
