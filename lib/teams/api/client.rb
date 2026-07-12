# frozen_string_literal: true

module Teams
  module Api
    class Client
      attr_reader :service_url, :http

      DEFAULT_OAUTH_URL = "https://token.botframework.com"

      attr_reader :conversations, :teams, :meetings, :users, :bots

      # Sub-clients are constructed eagerly like the other SDKs' ApiClient
      # constructors, which also keeps the shared client thread-safe.
      # oauth_url is the Bot Framework token service (cloud-dependent), used
      # by the user token and bot sign-in clients.
      def initialize(service_url:, http:, logger: nil, oauth_url: DEFAULT_OAUTH_URL)
        @service_url = service_url.sub(%r{/+\z}, "")
        @http = http
        @logger = logger
        @conversations = ConversationClient.new(service_url: @service_url, http:, logger:)
        @teams = TeamClient.new(service_url: @service_url, http:, logger:)
        @meetings = MeetingClient.new(service_url: @service_url, http:, logger:)
        @users = UserClient.new(oauth_url:, http:, logger:)
        @bots = BotClient.new(oauth_url:, http:, logger:)
      end
    end
  end
end
