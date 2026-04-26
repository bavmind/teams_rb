# frozen_string_literal: true

module Teams
  module Api
    class MessageActivity
      TEXT_FORMATS = %w[plain markdown xml].freeze

      attr_reader :text, :attachments, :text_format, :summary, :input_hint

      def initialize(text = nil, attachments: [], text_format: nil, summary: nil, input_hint: nil)
        @text = text
        @attachments = attachments
        @text_format = normalize_text_format(text_format)
        @summary = summary
        @input_hint = input_hint
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

      def to_h
        body = { "type" => "message" }
        body["text"] = text if text
        body["textFormat"] = text_format if text_format
        body["summary"] = summary if summary
        body["inputHint"] = input_hint if input_hint
        body["attachments"] = attachments unless attachments.empty?
        body
      end

      private

      def normalize_text_format(value)
        return nil if value.nil?

        normalized = value.to_s
        return normalized if TEXT_FORMATS.include?(normalized)

        raise ArgumentError, "text_format must be one of: #{TEXT_FORMATS.join(", ")}"
      end
    end
  end
end
