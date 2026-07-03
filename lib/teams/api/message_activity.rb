# frozen_string_literal: true

module Teams
  module Api
    class MessageActivity
      TEXT_FORMATS = %w[plain markdown xml extendedmarkdown].freeze
      FEEDBACK_MODES = %w[default custom].freeze
      AI_MESSAGE_ENTITY_TYPE = "https://schema.org/Message"

      attr_reader :id, :text, :attachments, :text_format, :summary, :input_hint, :entities, :channel_data

      def initialize(text = nil, id: nil, attachments: [], text_format: nil, summary: nil, input_hint: nil)
        @id = id
        @text = text
        @attachments = attachments
        @text_format = normalize_text_format(text_format)
        @summary = summary
        @input_hint = input_hint
        @entities = []
        @channel_data = {}
      end

      def add_text(value)
        @text = "#{text}#{value}"
        self
      end

      def add_quote(message_id, text = nil)
        @entities << QuotedReplyEntity.new("quotedReply" => { "messageId" => message_id })
        add_text(%(<quoted messageId="#{message_id}"/>))
        add_text(" #{text}") if text
        self
      end

      def prepend_quote(message_id)
        @entities << QuotedReplyEntity.new("quotedReply" => { "messageId" => message_id })
        placeholder = %(<quoted messageId="#{message_id}"/>)
        @text = text.to_s.strip.empty? ? placeholder : "#{placeholder} #{text}"
        self
      end

      def get_quoted_messages
        entities.select { |entity| quoted_reply_entity?(entity) }
      end

      def add_card(card)
        @attachments << {
          "contentType" => "application/vnd.microsoft.card.adaptive",
          "content" => card.respond_to?(:to_h) ? card.to_h : card
        }
        self
      end

      def with_text_format(text_format)
        @text_format = normalize_text_format(text_format)
        self
      end

      def with_id(id)
        @id = id
        self
      end

      def add_ai_generated
        entity = ensure_single_root_level_message_entity
        additional_types = Array(entity["additionalType"])
        return self if additional_types.include?("AIGeneratedContent")

        entity["additionalType"] = additional_types + ["AIGeneratedContent"]
        self
      end

      def add_citation(position, appearance)
        entity = ensure_single_root_level_message_entity
        entity["citation"] ||= []
        entity["citation"] << {
          "@type" => "Claim",
          "position" => position,
          "appearance" => citation_appearance(appearance).to_h
        }
        self
      end

      def add_feedback(mode = "default")
        @channel_data["feedbackLoop"] = { "type" => normalize_feedback_mode(mode) }
        @channel_data.delete("feedbackLoopEnabled")
        self
      end

      def to_h
        body = { "type" => "message" }
        body["id"] = id if id
        body["text"] = text if text
        body["textFormat"] = text_format if text_format
        body["summary"] = summary if summary
        body["inputHint"] = input_hint if input_hint
        body["attachments"] = attachments unless attachments.empty?
        body["entities"] = @entities.map { |entity| entity.respond_to?(:to_h) ? entity.to_h : entity } unless @entities.empty?
        body["channelData"] = channel_data unless channel_data.empty?
        body
      end

      private

      def quoted_reply_entity?(entity)
        entity_type(entity) == "quotedReply"
      end

      def ensure_single_root_level_message_entity
        entity = @entities.find { |item| entity_type(item) == AI_MESSAGE_ENTITY_TYPE }
        return entity if entity

        entity = {
          "type" => AI_MESSAGE_ENTITY_TYPE,
          "@type" => "Message",
          "@context" => "https://schema.org"
        }
        @entities << entity
        entity
      end

      def citation_appearance(appearance)
        appearance.is_a?(CitationAppearance) ? appearance : CitationAppearance.new(appearance || {})
      end

      def entity_type(entity)
        entity.respond_to?(:type) ? entity.type : entity["type"]
      end

      def normalize_text_format(value)
        return nil if value.nil?

        normalized = value.to_s
        return normalized if TEXT_FORMATS.include?(normalized)

        raise ArgumentError, "text_format must be one of: #{TEXT_FORMATS.join(", ")}"
      end

      def normalize_feedback_mode(value)
        normalized = value.to_s
        return normalized if FEEDBACK_MODES.include?(normalized)

        raise ArgumentError, "feedback mode must be one of: #{FEEDBACK_MODES.join(", ")}"
      end
    end
  end
end
