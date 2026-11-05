# frozen_string_literal: true

module Teams
  module OAuth
    DEFAULT_OAUTH_CARD_TEXT = "Please Sign In..."
    DEFAULT_SIGN_IN_BUTTON_TEXT = "Sign In"

    # A successful sign-in on a connection: the turn's context, the Token
    # Service response, and the connection it completed on.
    SignInEvent = Struct.new(:context, :token_response, :connection_name, keyword_init: true)

    # A failed sign-in. connection_name is nil when a signin/failure callback
    # cannot be attributed to a connection.
    SignInFailureEvent = Struct.new(:context, :connection_name, :code, :message, keyword_init: true)

    # The connection name with surrounding whitespace removed; a blank name
    # cannot address anything, so it raises.
    def self.normalize_connection_name(connection_name)
      normalized = connection_name.is_a?(String) ? connection_name.strip : ""
      raise ArgumentError, "OAuth connection name must not be blank." if normalized.empty?

      normalized
    end

    # The case-insensitive lookup key for a connection name, or nil for a
    # blank or non-string name (lookups are lenient, registration is strict).
    def self.lookup_key(connection_name)
      return nil unless connection_name.is_a?(String)

      normalized = connection_name.strip
      normalized.empty? ? nil : normalized.downcase
    end

    # One named OAuth connection plus the handlers attached to it, created
    # with app.add_oauth_flow. Mirrors the TypeScript, Python, and .NET
    # OAuthFlow.
    class Flow
      attr_reader :connection_name, :oauth_card_text, :sign_in_button_text

      def initialize(connection_name, oauth_card_text: DEFAULT_OAUTH_CARD_TEXT,
        sign_in_button_text: DEFAULT_SIGN_IN_BUTTON_TEXT, logger: nil)
        @connection_name = OAuth.normalize_connection_name(connection_name)
        @oauth_card_text = oauth_card_text
        @sign_in_button_text = sign_in_button_text
        @logger = logger
        @sign_in_handlers = []
        @sign_in_failure_handlers = []
      end

      # Called with a SignInEvent after a sign-in completes on this
      # connection. Handlers run in registration order, isolated from one
      # another: one that raises is logged and the rest still run.
      def on_sign_in(&block)
        raise ArgumentError, "handler block is required" unless block

        @sign_in_handlers << block
        self
      end

      # Called with a SignInFailureEvent when a sign-in on this connection
      # fails. A signin/failure callback carries no connection name, so it is
      # matched against the pending sign-in recorded when the flow started; if
      # that cannot be resolved (typically another process started it and
      # state is off), every registered flow is notified.
      def on_sign_in_failure(&block)
        raise ArgumentError, "handler block is required" unless block

        @sign_in_failure_handlers << block
        self
      end

      # Starts sign-in on this connection: returns the token when the user is
      # already signed in, otherwise sends the OAuth card and returns nil. The
      # card text options override the flow's defaults; the connection is
      # always this flow's.
      def sign_in(context, oauth_card_text: nil, sign_in_button_text: nil)
        context.sign_in(
          connection_name:,
          oauth_card_text: oauth_card_text || self.oauth_card_text,
          sign_in_button_text: sign_in_button_text || self.sign_in_button_text
        )
      end

      # Signs the user out of this connection.
      def sign_out(context)
        context.api.users.sign_out(
          user_id: context.activity.from.id,
          connection_name:,
          channel_id: context.activity.channel_id
        )
        nil
      end

      # The user's token for this connection, or nil when not signed in.
      # Token Service failures other than 404 raise.
      def get_token(context)
        context.get_user_token(connection_name:)
      end

      def signed_in?(context)
        !get_token(context).nil?
      end

      def sign_in_handlers?
        !@sign_in_handlers.empty?
      end

      def sign_in_failure_handlers?
        !@sign_in_failure_handlers.empty?
      end

      def invoke_sign_in_handlers(event)
        dispatch(@sign_in_handlers, event, "on_sign_in")
      end

      def invoke_sign_in_failure_handlers(event)
        dispatch(@sign_in_failure_handlers, event, "on_sign_in_failure")
      end

      def inspect
        "#<#{self.class.name} connection_name=#{connection_name.inspect}>"
      end

      private

      # A raising handler is a broken listener: it must not hide the rest or
      # turn a successful callback into a failed invoke response.
      def dispatch(handlers, event, kind)
        handlers.dup.each do |handler|
          handler.call(event)
        rescue StandardError => error
          @logger&.error(
            "#{kind} handler failed for connection #{connection_name.inspect}; continuing with later handlers: " \
            "#{error.class}: #{error.message}"
          )
        end
        nil
      end
    end

    # Case-insensitive, insertion-ordered collection of flows.
    class FlowRegistry
      include Enumerable

      def initialize
        @flows = {}
      end

      def add(flow)
        key = OAuth.lookup_key(flow.connection_name)
        if @flows.key?(key)
          raise ArgumentError, "An OAuth flow for connection '#{flow.connection_name}' is already registered. " \
            "Connection names are case-insensitive."
        end

        @flows[key] = flow
      end

      # The flow for a connection name (case-insensitive), or nil.
      def [](connection_name)
        @flows[OAuth.lookup_key(connection_name)]
      end

      def each(&block)
        return enum_for(:each) unless block

        @flows.values.each(&block)
        self
      end

      def names
        @flows.values.map(&:connection_name)
      end

      def size
        @flows.size
      end

      def empty?
        @flows.empty?
      end
    end
  end
end
