# frozen_string_literal: true

require "logger"

module Teams
  class App
    DEFAULT_MESSAGING_ENDPOINT = "/api/messages"

    attr_reader :api, :logger, :storage, :messaging_endpoint, :default_connection_name

    def client_id
      @token_manager.client_id
    end

    def initialize(
      client_id: ENV["CLIENT_ID"],
      client_secret: ENV["CLIENT_SECRET"],
      tenant_id: ENV["TENANT_ID"],
      service_url: ENV.fetch("SERVICE_URL", "https://smba.trafficmanager.net/teams"),
      cloud: CloudEnvironments.public,
      logger: Logger.new($stdout),
      storage: Storage::MemoryStore.new,
      api: nil,
      token_manager: nil,
      skip_auth: false,
      messaging_endpoint: DEFAULT_MESSAGING_ENDPOINT,
      default_connection_name: "graph"
    )
      @default_connection_name = default_connection_name
      @logger = logger
      @storage = storage
      @cloud = cloud
      @skip_auth = skip_auth
      @messaging_endpoint = normalize_messaging_endpoint(messaging_endpoint)
      @router = Router.new

      @token_manager = token_manager || Auth::TokenManager.from_env(client_id:, client_secret:, tenant_id:, cloud:)
      @api = api || Api::Client.new(
        service_url:,
        http: Common::HttpClient.new(token: -> { @token_manager.bot_token }),
        logger:,
        oauth_url: cloud.token_service_url
      )
      @jwt_validator = Auth::JwtValidator.new(
        client_id: @token_manager.client_id,
        tenant_id: @token_manager.credentials&.tenant_id,
        cloud:
      ) if @token_manager.client_id

      warn_missing_credentials
    end

    def to_rack
      RackApp.new(self)
    end

    def initialize!
      @token_manager.bot_token
      true
    end

    def use(&block)
      @router.use(&block)
      self
    end

    def on(name, &block)
      @router.on(name, &block)
      self
    end

    def on_message(pattern = nil, &block)
      @router.on_message(pattern, &block)
      self
    end

    def on_suggested_action_submit(&block)
      @router.on("suggested-action.submit", &block)
      self
    end

    # Registers a dialog (task module) open handler for task/fetch invokes.
    # With a dialog_id, only invokes whose card action data carries that
    # "dialog_id" value match. The handler's return value (a
    # Api::TaskModuleResponse or hash) becomes the invoke response body.
    def on_dialog_open(dialog_id = nil, &block)
      @router.on_dialog_open(dialog_id, &block)
      self
    end

    # Registers a dialog (task module) submit handler for task/submit
    # invokes, optionally filtered by the "action" value in the submit data.
    def on_dialog_submit(action = nil, &block)
      @router.on_dialog_submit(action, &block)
      self
    end

    # Sign-in invokes: signin/tokenExchange arrives for silent SSO token
    # exchange, signin/verifyState after interactive OAuth card sign-in.
    def on_signin_token_exchange(&block)
      @router.on_signin_token_exchange(&block)
      self
    end

    def on_signin_verify_state(&block)
      @router.on_signin_verify_state(&block)
      self
    end

    # Meeting start/end events (Teams posts them to bots installed in the
    # meeting chat when the meeting begins and ends).
    def on_meeting_start(&block)
      @router.on_meeting_start(&block)
      self
    end

    def on_meeting_end(&block)
      @router.on_meeting_end(&block)
      self
    end

    # Message extension handlers (on_message_ext_query, on_message_ext_submit,
    # on_message_ext_open, ...) route the composeExtension/* invokes with the
    # TypeScript/Python route names. Handler return values (typed responses
    # or hashes) become the invoke response body.
    Router::MESSAGE_EXTENSION_HANDLER_METHODS.each_key do |method_name|
      define_method(method_name) do |&block|
        @router.public_send(method_name, &block)
        self
      end
    end

    def on_message_update(&block)
      @router.on_message_update(&block)
      self
    end

    def on_edit_message(&block)
      @router.on_edit_message(&block)
      self
    end

    def on_undelete_message(&block)
      @router.on_undelete_message(&block)
      self
    end

    def process_inbound(payload, env: {})
      activity = Activity.new(payload)
      validate_inbound!(env, activity)

      conversation_reference = Api::ConversationReference.from_activity(activity)
      context = ActivityContext.new(
        app: self,
        activity:,
        conversation_reference:,
        stream: HttpStream.new(app: self, conversation_reference:)
      )
      result = run_handlers(context)
      context.stream.close

      return result if result.is_a?(Response)

      body = activity.invoke? ? invoke_response_body(result) : nil
      Response.new(status: 200, body:)
    rescue StreamCancelledError
      Response.new(status: 200)
    end

    # The TypeScript, Python, and .NET SDKs call this operation `send`.
    # Ruby already defines Object#send for dynamic dispatch, so the public
    # Ruby API uses `post` to avoid shadowing a core language method.
    def post(conversation_id, activity_or_text, service_url: nil)
      assert_string!(conversation_id, "conversation_id")

      send_activity(
        proactive_reference(conversation_id, service_url:),
        activity_or_text
      )
    end

    # Proactive threaded replies use a ";messageid=" conversation ID like the
    # TypeScript and Python SDKs; the service decides whether threading applies.
    def reply(conversation_id, activity_id_or_activity, activity_or_text = nil, service_url: nil)
      assert_string!(conversation_id, "conversation_id")

      if activity_or_text
        assert_string!(activity_id_or_activity, "activity_id")

        post(
          Teams.to_threaded_conversation_id(conversation_id, activity_id_or_activity),
          activity_or_text,
          service_url:
        )
      else
        post(conversation_id, activity_id_or_activity, service_url:)
      end
    end

    # Sugar over post: the SDKs update by sending an activity that already
    # carries an id, and post does exactly that. See AGENTS.md.
    def update(conversation_id, activity_id, activity_or_text, service_url: nil)
      assert_string!(conversation_id, "conversation_id")
      assert_string!(activity_id, "activity_id")

      post(conversation_id, activity_with_id(activity_id, activity_or_text), service_url:)
    end

    def send_activity(conversation_reference, activity_or_text)
      activity = activity_for_reference(conversation_reference, activity_or_text)
      targeted = targeted_activity?(activity)

      if targeted && conversation_reference.conversation.conversation_type == "personal"
        raise ArgumentError, "Targeted messages are not supported in 1:1 (personal) chats."
      end

      id = activity_id(activity)
      conversation_id = conversation_reference.conversation_id
      service_url = conversation_reference.service_url

      response = if id && targeted
        api.conversations.update_targeted_activity(conversation_id, id, activity, service_url:)
      elsif id
        api.conversations.update_activity(conversation_id, id, activity, service_url:)
      elsif targeted
        api.conversations.create_targeted_activity(conversation_id, activity, service_url:)
      else
        api.conversations.create_activity(conversation_id, activity, service_url:)
      end

      Api::SentActivity.merge(activity, response)
    end

    private

    # Invoke handler return values become the invoke response body, like the
    # TypeScript/Python SDKs. Only explicit response shapes count: Ruby
    # methods implicitly return their last expression, so an invoke handler
    # ending in ctx.post must not leak the SentActivity into the response.
    def invoke_response_body(result)
      case result
      when Api::TaskModuleResponse, Api::MessagingExtensionResponse, Api::MessagingExtensionActionResponse
        result.to_h
      when Hash
        Common::Hashes.deep_stringify_keys(result)
      end
    end

    def activity_with_id(activity_id, activity_or_text)
      outbound = normalize_activity(activity_or_text)
      body = outbound.respond_to?(:to_h) ? outbound.to_h : outbound
      body.merge("id" => activity_id)
    end

    # The same two startup warnings the TypeScript, Python, and .NET SDKs
    # log when no credentials are configured. Settled 2026-07-12: exact
    # upstream branches only; credentials-plus-skip_auth stays silent like
    # the other SDKs.
    def warn_missing_credentials
      return if @token_manager.client_id

      if @skip_auth
        logger&.warn(
          "No credentials configured (CLIENT_ID / CLIENT_SECRET / TENANT_ID), " \
          "but skip_auth is enabled. Bot will accept unauthenticated requests on #{@messaging_endpoint}."
        )
      else
        logger&.warn(
          "No credentials configured and skip_auth is not enabled. All incoming requests will be rejected. " \
          "Configure client authentication to securely receive messages, or set skip_auth: true for local development."
        )
      end
    end

    def validate_inbound!(env, activity)
      return if @skip_auth

      raise AuthenticationError, "CLIENT_ID is required for inbound validation" unless @jwt_validator

      @jwt_validator.validate!(env["HTTP_AUTHORIZATION"], service_url: activity.service_url)
    end

    def run_handlers(context)
      routes = @router.matching(context.activity)
      activity = context.activity
      logger&.debug(
        "Teams inbound #{activity.type}#{activity.name ? " #{activity.name}" : ""} " \
        "id=#{activity.id} matched #{routes.length} route(s)"
      )
      index = -1
      next_handler = nil
      next_handler = lambda do
        index += 1
        route = routes[index]
        return nil unless route

        if route.handler.arity >= 2
          route.handler.call(context, next_handler)
        else
          route.handler.call(context)
        end
      end
      next_handler.call
    end

    def proactive_reference(conversation_id, service_url:)
      Api::ConversationReference.new(
        bot: { "id" => @token_manager.client_id },
        conversation: { "id" => conversation_id },
        channel_id: "msteams",
        service_url: service_url || api.service_url
      )
    end

    # Merges only the sender and conversation from the reference, matching the
    # TypeScript and Python activity senders.
    def activity_for_reference(conversation_reference, activity_or_text)
      activity = normalize_activity(activity_or_text)
      body = activity.respond_to?(:to_h) ? activity.to_h : activity
      return body unless body.is_a?(Hash)

      body = body.dup
      body["from"] = conversation_reference.bot.to_h if conversation_reference.bot
      body["conversation"] = conversation_reference.conversation.to_h
      body
    end

    def activity_id(activity)
      return unless activity.is_a?(Hash)

      activity["id"] || activity[:id]
    end

    def targeted_activity?(activity)
      activity.is_a?(Hash) &&
        activity["type"] == "message" &&
        activity.dig("recipient", "isTargeted") == true
    end

    def assert_string!(value, name)
      return if value.is_a?(String)

      raise ArgumentError, "#{name} must be a String"
    end

    def normalize_activity(activity_or_text)
      case activity_or_text
      when String
        Api::MessageActivity.new(activity_or_text)
      when Cards::AdaptiveCard
        Api::MessageActivity.new.add_card(activity_or_text)
      when Hash
        Common::Hashes.deep_stringify_keys(activity_or_text)
      else
        activity_or_text
      end
    end

    def normalize_messaging_endpoint(value)
      endpoint = value.to_s.strip
      return endpoint if endpoint.start_with?("/") && !endpoint.empty?

      raise ArgumentError, "messaging_endpoint must be a non-empty path starting with '/'"
    end

  end
end
