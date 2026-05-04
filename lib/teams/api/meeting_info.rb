# frozen_string_literal: true

module Teams
  module Api
    class MeetingInfo < Model
      def id
        read("id")
      end

      def details
        value = read("details")
        value.is_a?(Hash) ? ActivityValue.new(value) : value
      end

      def conversation
        value = read("conversation")
        value ? ConversationAccount.new(value) : nil
      end

      def organizer
        value = read("organizer")
        value ? Account.new(value) : nil
      end
    end
  end
end
