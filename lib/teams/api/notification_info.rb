# frozen_string_literal: true

module Teams
  module Api
    class NotificationInfo < Model
      def alert
        read("alert")
      end

      def alert_in_meeting
        read("alertInMeeting", "alert_in_meeting")
      end

      def external_resource_url
        read("externalResourceUrl", "external_resource_url")
      end

      def to_h
        body = raw.dup
        body["alertInMeeting"] = alert_in_meeting unless alert_in_meeting.nil?
        body["externalResourceUrl"] = external_resource_url if external_resource_url
        body.delete("alert_in_meeting")
        body.delete("external_resource_url")
        body
      end
    end
  end
end
