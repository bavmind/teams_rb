# frozen_string_literal: true

module Teams
  class ActivityContext
    attr_reader :app, :activity, :conversation_reference, :extra

    def initialize(app:, activity:, conversation_reference:, extra: {})
      @app = app
      @activity = activity
      @conversation_reference = conversation_reference
      @extra = extra
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
      app.reply_to_activity(conversation_reference, activity.id, reply_activity(activity_or_text))
    end

    def typing
      post(Api::TypingActivity.new)
    end

    private

    def reply_activity(activity_or_text)
      outbound = normalize_activity(activity_or_text)
      body = outbound.respond_to?(:to_h) ? outbound.to_h : outbound
      return body unless body.is_a?(Hash)

      body = body.dup
      body["replyToId"] ||= activity.id
      if body["type"] == "message" && body["text"]
        body["text"] = [blockquote, body["text"]].compact.join("\r\n")
      end
      body
    end

    def blockquote
      return unless activity.message?

      preview = activity.text.to_s
      preview = "#{preview[0, 120]}..." if preview.length > 120

      activity_id = html_escape(activity.id.to_s)
      from_id = html_escape(activity.from.id.to_s)
      from_name = html_escape(activity.from.name.to_s)
      preview = html_escape(preview)

      <<~HTML.strip
        <blockquote itemscope="" itemtype="http://schema.skype.com/Reply" itemid="#{activity_id}">
        <strong itemprop="mri" itemid="#{from_id}">#{from_name}</strong><span itemprop="time" itemid="#{activity_id}"></span>
        <p itemprop="preview">#{preview}</p>
        </blockquote>
      HTML
    end

    def html_escape(value)
      value.gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
        .gsub('"', "&quot;")
        .gsub("'", "&#39;")
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
