# frozen_string_literal: true

module Teams
  module Api
    class TypingActivity
      attr_reader :text

      def initialize(text = nil)
        @text = text
      end

      def to_h
        body = { "type" => "typing" }
        body["text"] = text if text
        body
      end
    end
  end
end
