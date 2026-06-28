# frozen_string_literal: true

module Teams
  module Api
    class MessageActivity
      TEXT_FORMATS = %w[plain markdown xml extendedmarkdown].freeze
      AI_MESSAGE_ENTITY_TYPE = "https://schema.org/Message"

      attr_reader :text, :attachments, :text_format, :summary, :input_hint

      def initialize(text = nil, attachments: [], text_format: nil, summary: nil, input_hint: nil)
        @text = text
        @attachments = attachments
        @text_format = normalize_text_format(text_format)
        @summary = summary
        @input_hint = input_hint
        @entities = []
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

      def add_ai_generated
        entity = ensure_single_root_level_message_entity
        additional_types = Array(entity["additionalType"])
        return self if additional_types.include?("AIGeneratedContent")

        entity["additionalType"] = additional_types + ["AIGeneratedContent"]
        self
      end

      def to_h
        body = { "type" => "message" }
        body["text"] = text if text
        body["textFormat"] = text_format if text_format
        body["summary"] = summary if summary
        body["inputHint"] = input_hint if input_hint
        body["attachments"] = attachments unless attachments.empty?
        body["entities"] = @entities unless @entities.empty?
        body
      end

      private

      def ensure_single_root_level_message_entity
        entity = @entities.find { |item| item["type"] == AI_MESSAGE_ENTITY_TYPE }
        return entity if entity

        entity = {
          "type" => AI_MESSAGE_ENTITY_TYPE,
          "@type" => "Message",
          "@context" => "https://schema.org"
        }
        @entities << entity
        entity
      end

      def normalize_text_format(value)
        return nil if value.nil?

        normalized = value.to_s
        return normalized if TEXT_FORMATS.include?(normalized)

        raise ArgumentError, "text_format must be one of: #{TEXT_FORMATS.join(", ")}"
      end
    end
  end
end
