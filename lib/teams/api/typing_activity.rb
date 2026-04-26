# frozen_string_literal: true

module Teams
  module Api
    class TypingActivity
      def to_h
        { "type" => "typing" }
      end
    end
  end
end
