# frozen_string_literal: true

module Teams
  module Api
    # A participant's meeting-specific details: role and presence status.
    class Meeting < Model
      def role
        read("role")
      end

      def in_meeting
        read("inMeeting", "in_meeting")
      end
    end

    class MeetingParticipant < Model
      def user
        value = read("user")
        value ? Account.new(value) : nil
      end

      def meeting
        value = read("meeting")
        value ? Meeting.new(value) : nil
      end

      def conversation
        value = read("conversation")
        value ? ConversationAccount.new(value) : nil
      end
    end
  end
end
