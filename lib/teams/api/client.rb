# frozen_string_literal: true

module Teams
  module Api
    class Client
      attr_reader :service_url, :http

      attr_reader :conversations, :teams, :meetings

      # Sub-clients are constructed eagerly like the other SDKs' ApiClient
      # constructors, which also keeps the shared client thread-safe.
      def initialize(service_url:, http:, logger: nil)
        @service_url = service_url.sub(%r{/+\z}, "")
        @http = http
        @logger = logger
        @conversations = ConversationClient.new(service_url: @service_url, http:, logger:)
        @teams = TeamClient.new(service_url: @service_url, http:, logger:)
        @meetings = MeetingClient.new(service_url: @service_url, http:, logger:)
      end
    end
  end
end
