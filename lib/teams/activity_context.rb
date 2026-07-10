# frozen_string_literal: true

module Teams
  class ActivityContext
    attr_reader :app, :activity, :conversation_reference, :extra, :stream

    def initialize(app:, activity:, conversation_reference:, extra: {}, stream: nil)
      @app = app
      @activity = activity
      @conversation_reference = conversation_reference
      @extra = extra
      @stream = stream
    end

    def ref
      conversation_reference
    end

    def reference
      conversation_reference
    end

    def log
      app.logger
    end

    def storage
      app.storage
    end

    def api
      app.api
    end

    # The TypeScript, Python, and .NET SDKs call this operation `send`.
    # Ruby already defines Object#send for dynamic dispatch, so the public
    # Ruby API uses `post` to avoid shadowing a core language method.
    def post(activity_or_text)
      app.send_activity(conversation_reference, activity_or_text)
    end

    def reply(activity_or_text)
      return post(activity_or_text) unless activity.id

      quote(activity.id, activity_or_text)
    end

    def quote(message_id, activity_or_text)
      app.reply_to_activity(conversation_reference, message_id, quoted_activity(message_id, activity_or_text))
    end

    def update(activity_id, activity_or_text)
      app.update_activity(conversation_reference, activity_id, activity_or_text)
    end

    def typing(text = nil)
      post(Api::TypingActivity.new(text))
    end

    private

    def quoted_activity(message_id, activity_or_text)
      outbound = normalize_activity(activity_or_text)
      return outbound.prepend_quote(message_id) if outbound.is_a?(Api::MessageActivity)

      body = outbound.respond_to?(:to_h) ? outbound.to_h : outbound
      return body unless body.is_a?(Hash)

      body = body.dup
      prepend_quote_to_hash(body, message_id) if body["type"] == "message"
      body
    end

    def prepend_quote_to_hash(body, message_id)
      body["entities"] = Array(body["entities"]) + [
        Api::QuotedReplyEntity.new("quotedReply" => { "messageId" => message_id }).to_h
      ]
      placeholder = %(<quoted messageId="#{message_id}"/>)
      body["text"] = body["text"].to_s.strip.empty? ? placeholder : "#{placeholder} #{body["text"]}"
    end

    def normalize_activity(activity_or_text)
      case activity_or_text
      when String
        Api::MessageActivity.new(activity_or_text)
      when Cards::AdaptiveCard
        Api::MessageActivity.new.add_card(activity_or_text)
      else
        activity_or_text
      end
    end
  end
end
