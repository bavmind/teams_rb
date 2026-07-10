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
      app.send_activity(conversation_reference, apply_targeted_defaults(activity_or_text))
    end

    def reply(activity_or_text)
      return post(activity_or_text) unless activity.id
      # Replies to targeted inbound messages are targeted sends: no quoted
      # reply and no replyToId, matching the TypeScript and Python SDKs.
      return post(activity_or_text) if targeted_reply?(activity_or_text)

      quote(activity.id, activity_or_text)
    end

    def quote(message_id, activity_or_text)
      app.reply_to_activity(conversation_reference, message_id, quoted_activity(message_id, activity_or_text))
    end

    # Sugar over post: the SDKs update by sending an activity that already
    # carries an id, and post does exactly that. See AGENTS.md.
    def update(activity_id, activity_or_text)
      post(activity_with_id(activity_id, activity_or_text))
    end

    def typing(text = nil)
      post(Api::TypingActivity.new(text))
    end

    private

    def incoming_targeted_sender
      return nil unless activity.message?
      return nil unless activity.recipient.is_targeted == true

      activity.from
    end

    def apply_targeted_defaults(activity_or_text)
      sender = incoming_targeted_sender
      return activity_or_text unless sender

      body = activity_body(activity_or_text)
      return activity_or_text unless body

      if body["type"] == "message" && !body["id"] && !body.key?("recipient")
        body["recipient"] = sender.to_h.merge("isTargeted" => true)
      end

      return body unless targeted_outbound?(body)

      add_targeted_message_info(body, activity.id)
      body
    end

    def targeted_reply?(activity_or_text)
      return false unless incoming_targeted_sender

      body = activity_body(activity_or_text)
      return false unless body
      return false unless body["type"] == "message"

      (!body["id"] && !body.key?("recipient")) || targeted_outbound?(body)
    end

    def targeted_outbound?(body)
      body["type"] == "message" && body.dig("recipient", "isTargeted") == true
    end

    def activity_body(activity_or_text)
      outbound = normalize_activity(activity_or_text)
      body = outbound.respond_to?(:to_h) ? outbound.to_h : outbound
      body.is_a?(Hash) ? body.dup : nil
    end

    # Hash counterpart of MessageActivity#add_targeted_message_info: strips
    # quotedReply artifacts and adds the prompt preview entity once.
    def add_targeted_message_info(body, message_id)
      entities = Array(body["entities"]).reject do |entity|
        entity.is_a?(Hash) && entity["type"] == "quotedReply"
      end
      body["text"] = body["text"].gsub(%(<quoted messageId="#{message_id}"/>), "").strip if body["text"]

      unless entities.any? { |entity| entity.is_a?(Hash) && entity["type"] == "targetedMessageInfo" }
        entities << { "type" => "targetedMessageInfo", "messageId" => message_id }
      end

      body["entities"] = entities
    end

    def activity_with_id(activity_id, activity_or_text)
      outbound = normalize_activity(activity_or_text)
      body = outbound.respond_to?(:to_h) ? outbound.to_h : outbound
      body.merge("id" => activity_id)
    end

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
