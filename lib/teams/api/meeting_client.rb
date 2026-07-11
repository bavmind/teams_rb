# frozen_string_literal: true

require "uri"

module Teams
  module Api
    class MeetingClient
      attr_reader :service_url, :http

      def initialize(service_url:, http:, logger: nil)
        @service_url = service_url.sub(%r{/+\z}, "")
        @http = http
        @logger = logger
      end

      def get_by_id(meeting_id, service_url: nil)
        path = "/v1/meetings/#{escape(meeting_id)}"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API GET #{url}")
        MeetingInfo.new(http.get(url))
      end

      # participant_id is the user's AAD object id; tenant_id is required by
      # the service.
      def get_participant(meeting_id, participant_id, tenant_id, service_url: nil)
        path = "/v1/meetings/#{escape(meeting_id)}/participants/#{escape(participant_id)}"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API GET #{url}")
        MeetingParticipant.new(http.get(url, params: { "tenantId" => tenant_id }))
      end

      # Sends a targeted in-meeting notification. Returns nil when every
      # recipient succeeded (202); returns a MeetingNotificationResponse with
      # per-recipient failures on partial success (207).
      def send_notification(meeting_id, params, service_url: nil)
        body = Common::Hashes.deep_stringify_keys(params.respond_to?(:to_h) ? params.to_h : params)
        body["type"] ||= "targetedMeetingNotification"

        path = "/v1/meetings/#{escape(meeting_id)}/notification"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API POST #{url}")
        response = http.post(url, json: body)
        response ? MeetingNotificationResponse.new(response) : nil
      end

      private

      def absolute(path, service_url: nil)
        "#{(service_url || self.service_url).sub(%r{/+\z}, "")}#{path}"
      end

      def escape(value)
        URI.encode_www_form_component(value.to_s)
      end
    end
  end
end
