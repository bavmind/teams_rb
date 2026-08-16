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
      # by the user token and bot sign-in clients. token_provider is a
      # callable(agentic_identity) returning a bearer token; it enables
      # for_agentic_identity scoping (the App wires it to its TokenManager).
      def initialize(service_url:, http:, logger: nil, oauth_url: DEFAULT_OAUTH_URL, token_provider: nil)
        @service_url = service_url.sub(%r{/+\z}, "")
        @http = http
        @logger = logger
        @oauth_url = oauth_url
        @token_provider = token_provider
        @conversations = ConversationClient.new(service_url: @service_url, http:, logger:)
        @teams = TeamClient.new(service_url: @service_url, http:, logger:)
        @meetings = MeetingClient.new(service_url: @service_url, http:, logger:)
        @users = UserClient.new(oauth_url:, http:, logger:)
        @bots = BotClient.new(oauth_url:, http:, logger:)
      end

      # Returns a client scoped to an Agent 365 identity (and optionally a
      # different service URL): requests authenticate with the identity's
      # agentic token instead of the app token. The other SDKs call this
      # clone(); Ruby avoids shadowing Object#clone, like post vs send.
      # A nil identity scopes back to the app token.
      def for_agentic_identity(agentic_identity, service_url: nil)
        unless @token_provider
          raise Error, "This API client was constructed without a token provider; agentic scoping is unavailable."
        end

        identity = agentic_identity
        self.class.new(
          service_url: service_url || @service_url,
          http: Common::HttpClient.new(token: -> { @token_provider.call(identity) }),
          logger: @logger,
          oauth_url: @oauth_url,
          token_provider: @token_provider
        )
      end
    end
  end
end
