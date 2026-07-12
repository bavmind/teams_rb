# frozen_string_literal: true

module Teams
  module Api
    class MeetingNotificationRecipientFailure < Model
      def recipient_mri
        read("recipientMri", "recipient_mri")
      end

      def error_code
        read("errorCode", "error_code")
      end

      def failure_reason
        read("failureReason", "failure_reason")
      end
    end

    # Returned on partial success (HTTP 207) of a meeting notification; the
    # client returns nil instead when every recipient succeeded (HTTP 202).
    class MeetingNotificationResponse < Model
      def recipients_failure_info
        Array(read("recipientsFailureInfo", "recipients_failure_info")).map do |failure|
          MeetingNotificationRecipientFailure.new(failure)
        end
      end
    end
  end
end
