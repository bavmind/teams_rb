# frozen_string_literal: true

module Teams
  module Api
    class ConversationResource < Model
      def id
        read("id")
      end

      def activity_id
        read("activityId", "activity_id")
      end

      def service_url
        read("serviceUrl", "service_url")
      end
    end
  end
end
