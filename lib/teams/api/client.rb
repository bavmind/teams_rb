# frozen_string_literal: true

require "uri"

module Teams
  module Api
    class Client
      attr_reader :service_url, :http

      def initialize(service_url:, http:, logger: nil)
        @service_url = service_url.sub(%r{/+\z}, "")
        @http = http
        @logger = logger
      end

      def send_to_conversation(conversation_id, activity, service_url: nil)
        path = "/v3/conversations/#{escape(conversation_id)}/activities"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API POST #{url}")
        http.post(url, json: activity_to_h(activity))
      end

      def reply_to_activity(conversation_id, activity_id, activity, service_url: nil)
        path = "/v3/conversations/#{escape(conversation_id)}/activities/#{escape(activity_id)}"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API POST #{url}")
        http.post(url, json: activity_to_h(activity))
      end

      private

      def activity_to_h(activity)
        case activity
        when String
          MessageActivity.new(activity).to_h
        when Hash
          activity
        else
          activity.respond_to?(:to_h) ? activity.to_h : activity
        end
      end

      def absolute(path, service_url: nil)
        "#{(service_url || self.service_url).sub(%r{/+\z}, "")}#{path}"
      end

      def escape(value)
        URI.encode_www_form_component(value.to_s)
      end
    end
  end
end
