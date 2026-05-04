# frozen_string_literal: true

module Teams
  module Api
    class ChannelData < Model
      def tenant
        wrap(read("tenant"), TenantInfo)
      end

      def team
        wrap(read("team"), TeamInfo)
      end

      def channel
        wrap(read("channel"), ChannelInfo)
      end

      def meeting
        wrap(read("meeting"), MeetingInfo)
      end

      def notification
        wrap(read("notification"), NotificationInfo)
      end

      def event_type
        read("eventType", "event_type")
      end

      def settings
        value = read("settings")
        value.is_a?(Hash) ? ActivityValue.new(value) : value
      end

      def feedback_loop_enabled
        read("feedbackLoopEnabled", "feedback_loop_enabled")
      end

      def feedback_loop
        value = read("feedbackLoop", "feedback_loop")
        value.is_a?(Hash) ? ActivityValue.new(value) : value
      end

      def stream_id
        read("streamId", "stream_id")
      end

      def stream_type
        read("streamType", "stream_type")
      end

      def stream_sequence
        read("streamSequence", "stream_sequence")
      end

      def to_h
        body = raw.dup
        body["tenant"] = tenant.to_h if tenant
        body["team"] = team.to_h if team
        body["channel"] = channel.to_h if channel
        body["meeting"] = meeting.to_h if meeting
        body["notification"] = notification.to_h if notification
        body["eventType"] = event_type if event_type
        body["settings"] = settings.to_h if settings.respond_to?(:to_h)
        body["feedbackLoopEnabled"] = feedback_loop_enabled unless feedback_loop_enabled.nil?
        body["feedbackLoop"] = feedback_loop.to_h if feedback_loop.respond_to?(:to_h)
        body["streamId"] = stream_id if stream_id
        body["streamType"] = stream_type if stream_type
        body["streamSequence"] = stream_sequence if stream_sequence
        body.delete("event_type")
        body.delete("feedback_loop_enabled")
        body.delete("feedback_loop")
        body.delete("stream_id")
        body.delete("stream_type")
        body.delete("stream_sequence")
        body
      end

      private

      def wrap(value, klass)
        value ? klass.new(value) : nil
      end
    end
  end
end
