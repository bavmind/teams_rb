# frozen_string_literal: true

module Teams
  module Api
    class Client
      attr_reader :service_url, :http

      def initialize(service_url:, http:, logger: nil)
        @service_url = service_url.sub(%r{/+\z}, "")
        @http = http
        @logger = logger
      end

      def conversations
        @conversations ||= ConversationClient.new(service_url:, http:, logger: @logger)
      end

      def teams
        @teams ||= TeamClient.new(service_url:, http:, logger: @logger)
      end

      def meetings
        @meetings ||= MeetingClient.new(service_url:, http:, logger: @logger)
      end
    end
  end
end
