# frozen_string_literal: true

module Teams
  module Api
    class ActivityValue < Model
      # The invoke payload's data, e.g. dialog submit form values plus the
      # card action's data (dialog_id / action routing keys).
      def data
        read("data")
      end

      # The message extension command that fired (query/submit/fetchTask).
      def command_id
        read("commandId", "command_id")
      end

      # Message extension query parameters: [{"name" => ..., "value" => ...}].
      def parameters
        Array(read("parameters"))
      end

      # Meeting start/end event fields. Teams sends these PascalCase on the
      # wire (Id, JoinUrl, Title, MeetingType, StartTime, EndTime).
      def id
        read("Id", "id")
      end

      def title
        read("Title", "title")
      end

      def meeting_type
        read("MeetingType", "meetingType", "meeting_type")
      end

      def join_url
        read("JoinUrl", "joinUrl", "join_url")
      end

      def start_time
        read("StartTime", "startTime", "start_time")
      end

      def end_time
        read("EndTime", "endTime", "end_time")
      end
    end
  end
end
