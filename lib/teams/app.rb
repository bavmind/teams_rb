# frozen_string_literal: true

require "logger"

module Teams
  class App
    DEFAULT_MESSAGING_ENDPOINT = "/api/messages"
    DANGEROUSLY_ALLOW_UNAUTHENTICATED_REQUESTS_ENV_VAR = "DANGEROUSLY_ALLOW_UNAUTHENTICATED_REQUESTS"
    TRUE_ENV_VALUES = %w[1 true yes on].freeze
    FALSE_ENV_VALUES = %w[0 false no off].freeze

    # files_downloader and oauth_registry are plumbing for ActivityContext.
    attr_reader :api, :logger, :storage, :messaging_endpoint, :default_connection_name, :graph,
      :files_downloader, :oauth_registry

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
      dangerously_allow_unauthenticated_requests: nil,
      skip_auth: nil,
      messaging_endpoint: DEFAULT_MESSAGING_ENDPOINT,
      default_connection_name: "graph",
      state: nil
    )
      @default_connection_name = default_connection_name
      @sign_in_handlers = []
      @sign_in_failure_handlers = []
      @error_handlers = []
      @oauth_registry = OAuth::FlowRegistry.new
      @state_option = state
      @functions = {}
      @logger = logger
      @storage = storage
      @cloud = cloud
      @dangerously_allow_unauthenticated_requests = resolve_unauthenticated_requests_option(
        dangerously_allow_unauthenticated_requests, skip_auth
      )
      @messaging_endpoint = normalize_messaging_endpoint(messaging_endpoint)
      @router = Router.new
      @state_loader = create_state_loader(state)

      @token_manager = token_manager || Auth::TokenManager.from_env(client_id:, client_secret:, tenant_id:, cloud:)
      @api = api || Api::Client.new(
        service_url:,
        http: Common::HttpClient.new(token: -> { @token_manager.bot_token }),
        logger:,
        oauth_url: cloud.token_service_url,
        token_provider: method(:token_for_agentic_identity)
      )
      @jwt_validator = Auth::JwtValidator.new(
        client_id: @token_manager.client_id,
        tenant_id: @token_manager.credentials&.tenant_id,
        cloud:
      ) if @token_manager.client_id

      # Graph base URL derives from the cloud's graph scope host (sovereign
      # clouds), like the TypeScript SDK; the app-identity client requests
      # app-only tokens through the client-credentials flow.
      graph_root = cloud.graph_scope.to_s[%r{\Ahttps?://[^/]+}]
      @graph_base_url_root = graph_root
      @graph = Graph::Client.new(
        token: -> { @token_manager.token_for(cloud.graph_scope, @token_manager.credentials&.tenant_id || cloud.login_tenant) },
        base_url_root: graph_root
      )

      # One plain connection for inbound file downloads, shared across turns.
      @files_downloader = Files::Downloader.new(logger:)

      @oauth_handlers = OAuth::Handlers.new(self)
      register_default_oauth_handlers
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
    # exchange, signin/verifyState after interactive OAuth card sign-in,
    # signin/failure when the Teams client reports a failed SSO attempt.
    # Default handlers registered at construction complete these flows and
    # fire on_oauth_sign_in / on_error; handlers registered here run after them.
    def on_signin_token_exchange(&block)
      @router.on_signin_token_exchange(&block)
      self
    end

    def on_signin_verify_state(&block)
      @router.on_signin_verify_state(&block)
      self
    end

    def on_signin_failure(&block)
      @router.on_signin_failure(&block)
      self
    end

    # message/submitAction invokes; on_message_submit_feedback filters to
    # feedback-loop submissions (thumbs up/down from add_feedback).
    def on_message_submit(&block)
      @router.on_message_submit(&block)
      self
    end

    def on_message_submit_feedback(&block)
      @router.on_message_submit_feedback(&block)
      self
    end

    # application/search invokes from Adaptive Card dynamic typeahead
    # Input.ChoiceSet queries; the handler's return (Api::SearchResponse or
    # hash) becomes the invoke response body.
    def on_card_search(&block)
      @router.on_card_search(&block)
      self
    end

    # App-level OAuth events use the on_oauth_ prefix, which keeps them apart
    # from the on_signin_* invoke routes on this object.

    # Called with (ctx, token_response) whenever a sign-in completes through
    # the default token-exchange or verify-state handlers.
    def on_oauth_sign_in(&block)
      @sign_in_handlers << block
      self
    end

    def on_sign_in(&block)
      warn("App#on_sign_in is deprecated; use App#on_oauth_sign_in.", uplevel: 1, category: :deprecated)
      on_oauth_sign_in(&block)
    end

    # Called with (error, activity) when a default OAuth handler hits an
    # unexpected failure or the Teams client reports a sign-in failure.
    def on_error(&block)
      @error_handlers << block
      self
    end

    # Called with an OAuth::SignInFailureEvent when the Teams client reports
    # a failed sign-in (the signin/failure invoke). Terminal Token Service
    # errors reach only the flows' own on_sign_in_failure handlers.
    def on_oauth_sign_in_failure(&block)
      @sign_in_failure_handlers << block
      self
    end

    # Registers a named OAuth connection and returns its OAuth::Flow, like
    # the Python SDK's add_oauth_flow. Connection names are case-insensitive
    # and must be unique. Registering a flow turns on per-turn state when the
    # state: option was left unset, because connection-less callbacks need
    # somewhere to record which connection a sign-in started on; pass
    # state: false to opt out (pending sign-ins then use a bounded
    # process-local cache).
    def add_oauth_flow(connection_name, oauth_card_text: OAuth::DEFAULT_OAUTH_CARD_TEXT,
      sign_in_button_text: OAuth::DEFAULT_SIGN_IN_BUTTON_TEXT)
      flow = @oauth_registry.add(
        OAuth::Flow.new(connection_name, oauth_card_text:, sign_in_button_text:, logger:)
      )
      # Only after the registry accepted it, so a rejected duplicate cannot
      # switch state on.
      if @state_option.nil? && @state_loader.nil?
        @state_loader = create_state_loader(true)
        logger&.debug(
          "Enabled per-turn state because an OAuth flow was registered and no state option was set. " \
          "Pass state: false to opt out, or state: true / StateOptions to choose the storage."
        )
      end
      flow
    end

    # The registered flow for a connection (case-insensitive); raises when
    # none is registered.
    def get_oauth_flow(connection_name)
      flow = @oauth_registry[connection_name]
      return flow if flow

      registered = @oauth_registry.names.join(", ")
      registered = "<none>" if registered.empty?
      raise ArgumentError,
        "No OAuth flow registered for connection '#{connection_name}'. Registered connections: #{registered}."
    end

    def emit_sign_in(context, token_response)
      @sign_in_handlers.each { |handler| handler.call(context, token_response) }
    end

    def emit_sign_in_failure(event)
      @sign_in_failure_handlers.each { |handler| handler.call(event) }
    end

    # Process-local pending sign-ins, used when per-turn state is off.
    # Plumbing for ActivityContext#sign_in.
    def oauth_pending_cache
      @oauth_handlers.pending_cache
    end

    def emit_error(error, activity: nil)
      @error_handlers.each { |handler| handler.call(error, activity) }
    end

    # Registers a remote function callable from tabs via
    # POST /api/functions/{name}. Requests carry an Entra token for the tab
    # user, validated against the app's client id and tenant; the handler
    # receives a FunctionContext and its return value becomes the JSON
    # response body.
    def on_function(name, &block)
      raise ArgumentError, "handler block is required" unless block

      @functions[name.to_s] = block
      self
    end

    def process_function(name, data, env: {})
      handler = @functions[name.to_s]
      unless handler
        return Response.new(status: 404, body: { "detail" => "function #{name.inspect} is not registered" })
      end

      context, error = build_function_context(name.to_s, data, env)
      unless context
        logger&.warn("Rejected function call #{name.inspect}: #{error}")
        return Response.new(status: 401, body: { "detail" => error })
      end

      result = handler.call(context)
      body = result.respond_to?(:to_h) ? result.to_h : result
      # Function responses always carry valid JSON: callers fetch and parse
      # them, so a nil handler return becomes an empty object rather than an
      # empty body with a JSON content type.
      Response.new(status: 200, body: body.nil? ? {} : body)
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

    # conversationUpdate activities plus their channel/team lifecycle
    # sub-events (on_channel_created, on_team_renamed, ...), routed by
    # channelData.eventType with the Python method names.
    def on_conversation_update(&block)
      @router.on_conversation_update(&block)
      self
    end

    Router::CONVERSATION_UPDATE_EVENTS.each_key do |method_name|
      define_method(method_name) do |&block|
        @router.public_send(method_name, &block)
        self
      end
    end

    # Agent 365 agentLifecycle events plus their per-variant routes
    # (on_agentic_user_identity_created, on_agentic_user_enabled, ...),
    # discriminated by the activity-level valueType.
    def on_agent_lifecycle(&block)
      @router.on_agent_lifecycle(&block)
      self
    end

    Router::AGENT_LIFECYCLE_EVENTS.each_key do |method_name|
      define_method(method_name) do |&block|
        @router.public_send(method_name, &block)
        self
      end
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
      # Agentic activities carry the identity on the recipient account; the
      # whole turn (context and stream) is scoped to it so replies
      # authenticate as the agent, like the other SDKs' per-turn clients.
      agentic_identity = activity.recipient.agentic_identity
      turn_api = agentic_identity ? api.for_agentic_identity(agentic_identity) : api
      context = ActivityContext.new(
        app: self,
        activity:,
        conversation_reference:,
        api: turn_api,
        stream: HttpStream.new(app: self, conversation_reference:, api: turn_api),
        files_credential: files_credential(activity, agentic_identity),
        files_bot_api_credential: files_bot_api_credential(activity, agentic_identity, turn_api),
        state: load_turn_state(activity)
      )
      processing_completed = false
      begin
        result = run_handlers(context)
        context.stream.close
        processing_completed = true
      ensure
        persist_turn_state(context, processing_completed)
      end

      return result if result.is_a?(Response)

      body = activity.invoke? ? invoke_response_body(result) : nil
      Response.new(status: 200, body:)
    end

    # Builds an Api::AgenticIdentity for proactive agentic operations: the
    # blueprint defaults to this app's client id and the tenant to the
    # configured credentials tenant, like the Python SDK.
    def agentic_identity(agentic_app_id: nil, agentic_user_id: nil, tenant_id: nil, agentic_app_blueprint_id: nil)
      Api::AgenticIdentity.new(
        agentic_app_blueprint_id: agentic_app_blueprint_id || client_id,
        agentic_app_id:,
        agentic_user_id:,
        tenant_id: tenant_id || @token_manager.credentials&.tenant_id
      )
    end

    # The TypeScript, Python, and .NET SDKs call this operation `send`.
    # Ruby already defines Object#send for dynamic dispatch, so the public
    # Ruby API uses `post` to avoid shadowing a core language method.
    def post(conversation_id, activity_or_text, service_url: nil, agentic_identity: nil)
      assert_string!(conversation_id, "conversation_id")

      send_activity(
        proactive_reference(conversation_id, service_url:),
        activity_or_text,
        api: agentic_identity ? api.for_agentic_identity(agentic_identity) : api
      )
    end

    # Proactive threaded replies use a ";messageid=" conversation ID like the
    # TypeScript and Python SDKs; the service decides whether threading applies.
    def reply(conversation_id, activity_id_or_activity, activity_or_text = nil, service_url: nil, agentic_identity: nil)
      assert_string!(conversation_id, "conversation_id")

      if activity_or_text
        assert_string!(activity_id_or_activity, "activity_id")

        post(
          Teams.to_threaded_conversation_id(conversation_id, activity_id_or_activity),
          activity_or_text,
          service_url:,
          agentic_identity:
        )
      else
        post(conversation_id, activity_id_or_activity, service_url:, agentic_identity:)
      end
    end

    # Sugar over post: the SDKs update by sending an activity that already
    # carries an id, and post does exactly that. See AGENTS.md.
    def update(conversation_id, activity_id, activity_or_text, service_url: nil, agentic_identity: nil)
      assert_string!(conversation_id, "conversation_id")
      assert_string!(activity_id, "activity_id")

      post(conversation_id, activity_with_id(activity_id, activity_or_text), service_url:, agentic_identity:)
    end

    def send_activity(conversation_reference, activity_or_text, api: self.api)
      activity = activity_for_reference(conversation_reference, activity_or_text)
      targeted = targeted_activity?(activity)
      id = activity_id(activity)
      conversation_id = conversation_reference.conversation_id
      service_url = conversation_reference.service_url

      response = if id && targeted
        # The recipient of an existing targeted message cannot change: it only
        # selects the targeted endpoint and is dropped from the payload, like
        # the TypeScript and Python SDKs. The returned activity keeps it.
        api.conversations.update_targeted_activity(conversation_id, id, activity.except("recipient"), service_url:)
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
      when Api::TaskModuleResponse, Api::MessagingExtensionResponse, Api::MessagingExtensionActionResponse,
           Api::SearchResponse
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

    # Validates a remote function request like the TypeScript/Python SDKs:
    # required client headers, an Entra bearer token verified against the
    # app's client id/tenant, and the oid/tid/name claims. Returns
    # [context, nil] or [nil, error_message].
    def build_function_context(name, data, env)
      auth_header = env["HTTP_AUTHORIZATION"].to_s
      app_session_id = env["HTTP_X_TEAMS_APP_SESSION_ID"].to_s
      page_id = env["HTTP_X_TEAMS_PAGE_ID"].to_s

      return [nil, "missing X-Teams-App-Session-Id header"] if app_session_id.empty?
      return [nil, "missing X-Teams-Page-Id header"] if page_id.empty?
      return [nil, "missing Authorization bearer token"] if auth_header.empty?
      return [nil, "Token validator not configured"] unless @jwt_validator

      begin
        payload = @jwt_validator.validate!(auth_header)
      rescue AuthenticationError => error
        return [nil, error.message]
      end

      %w[oid tid name].each do |claim|
        return [nil, "missing #{claim} claim in token payload"] if payload[claim].to_s.empty?
      end

      context = FunctionContext.new(
        app: self,
        function_name: name,
        data:,
        app_session_id:,
        page_id:,
        auth_token: auth_header.split(" ", 2).last,
        tenant_id: payload["tid"],
        user_id: payload["oid"],
        user_name: payload["name"],
        app_id: payload["appId"],
        channel_id: presence(env["HTTP_X_TEAMS_CHANNEL_ID"]),
        chat_id: presence(env["HTTP_X_TEAMS_CHAT_ID"]),
        meeting_id: presence(env["HTTP_X_TEAMS_MEETING_ID"]),
        message_id: presence(env["HTTP_X_TEAMS_MESSAGE_ID"]),
        sub_page_id: presence(env["HTTP_X_TEAMS_SUB_PAGE_ID"]),
        team_id: presence(env["HTTP_X_TEAMS_TEAM_ID"])
      )
      [context, nil]
    end

    def presence(value)
      value.to_s.empty? ? nil : value
    end

    # Default OAuth handlers (OAuth::Handlers), registered first on the signin
    # routes so they complete the flows and chain to user handlers via next.
    def register_default_oauth_handlers
      handlers = @oauth_handlers
      @router.on_signin_token_exchange { |ctx, nxt| handlers.token_exchange(ctx, nxt) }
      @router.on_signin_verify_state { |ctx, nxt| handlers.verify_state(ctx, nxt) }
      @router.on_signin_failure { |ctx, nxt| handlers.failure(ctx, nxt) }
    end
    
    # Resolves the state: option like the Python SDK: nil/false disables
    # state, true enables it on the app's storage, State::StateOptions
    # configures the storage and key prefix.
    def create_state_loader(state)
      return nil unless state

      options = state == true ? State::StateOptions.new : state
      unless options.is_a?(State::StateOptions)
        raise ArgumentError, "state: must be true, false, nil, or a Teams::State::StateOptions"
      end

      storage = options.storage || @storage
      if storage.is_a?(Storage::MemoryStore)
        @logger&.warn(
          "State is enabled with in-memory storage (MemoryStore): per-turn state is lost on restart " \
          "and is not shared across instances."
        )
      end
      State::TurnStateLoader.new(storage:, key_prefix: options.key_prefix, logger: @logger)
    end

    # Loads the conversation scope and the user scope (keyed by the
    # activity's from identity) when state is enabled; nil otherwise.
    def load_turn_state(activity)
      return nil unless @state_loader

      conversation_id = activity.conversation&.id
      return nil if conversation_id.to_s.empty?

      user_id = activity.from&.id
      @state_loader.load(conversation_id, user_id.to_s.empty? ? nil : user_id)
    end

    # Saves dirty scopes and seals the state at the end of the turn, also
    # when a handler raised. A save failure is reported through on_error and
    # re-raised only when the turn itself succeeded, so it never masks the
    # handler's error.
    def persist_turn_state(context, processing_completed)
      container = context.state
      return unless @state_loader && container

      begin
        container.save
      ensure
        container.seal
      end
    rescue StandardError => error
      begin
        emit_error(error, activity: context.activity)
      rescue StandardError => handler_error
        logger&.error("Error handler failed while reporting a state persistence failure: #{handler_error.message}")
      end
      raise if processing_completed
    end

    # The Graph credential for the turn's file reads, resolved only when a
    # Graph read happens. An agentic user reads as itself, never the app: an
    # app-only token sees what the app may read tenant-wide, a different set
    # from what was shared with the agent, like the other SDKs.
    def files_credential(activity, agentic_identity)
      tenant_id = activity.conversation&.tenant_id || activity.channel_data&.tenant&.id
      token = if agentic_identity
        -> { agentic_graph_token(agentic_identity, tenant_id) }
      else
        -> { @token_manager.token_for(@cloud.graph_scope, tenant_id || @token_manager.credentials&.tenant_id || @cloud.login_tenant) }
      end

      Files::GraphCredential.new(
        actor: agentic_identity ? "agentic_user" : "app",
        token:,
        base_url_root: @graph_base_url_root
      )
    end

    # Inline images are read with the turn's Bot API token (the agentic
    # identity's when the turn is scoped to one), resolved only on download
    # and sent only under the activity's service URL.
    def files_bot_api_credential(activity, agentic_identity, turn_api)
      Files::BotApiCredential.new(
        actor: agentic_identity ? "agentic_user" : "app",
        service_url: activity.service_url,
        token: lambda do
          token = turn_api.http.token
          token.respond_to?(:call) ? token.call : token
        end
      )
    end

    # The identity's own tenant wins, then the tenant the activity arrived
    # from; TokenManager raises when neither is known rather than acquiring
    # in the wrong directory.
    def agentic_graph_token(identity, tenant_id)
      return nil if identity.agentic_app_id.to_s.empty? || identity.agentic_user_id.to_s.empty?

      @token_manager.agentic_user_token(
        @cloud.graph_scope,
        agentic_app_id: identity.agentic_app_id,
        agentic_user_id: identity.agentic_user_id,
        tenant_id: identity.tenant_id || tenant_id
      )
    end

    # Resolves the auth-bypass setting like the Python SDK: the explicit
    # option wins, then the deprecated skip_auth alias, then the env var,
    # defaulting to false. Passing skip_auth always warns, even when the
    # new option overrides it.
    def resolve_unauthenticated_requests_option(explicit, skip_auth)
      unless skip_auth.nil?
        warn("skip_auth is deprecated; use dangerously_allow_unauthenticated_requests instead.", uplevel: 2)
      end
      return explicit unless explicit.nil?
      return skip_auth unless skip_auth.nil?

      parse_bool_env_var(DANGEROUSLY_ALLOW_UNAUTHENTICATED_REQUESTS_ENV_VAR) || false
    end

    def parse_bool_env_var(name)
      value = ENV[name].to_s.strip.downcase
      return nil if value.empty?
      return true if TRUE_ENV_VALUES.include?(value)
      return false if FALSE_ENV_VALUES.include?(value)

      raise ArgumentError, "#{name} must be a boolean value: true/false, 1/0, yes/no, or on/off."
    end

    # The same two startup warnings the TypeScript, Python, and .NET SDKs
    # log when no credentials are configured. Settled 2026-07-12: exact
    # upstream branches only; credentials-plus-bypass stays silent like
    # the other SDKs.
    def warn_missing_credentials
      return if @token_manager.client_id

      if @dangerously_allow_unauthenticated_requests
        logger&.warn(
          "No credentials configured (CLIENT_ID / CLIENT_SECRET / TENANT_ID), " \
          "but dangerously_allow_unauthenticated_requests is enabled. " \
          "Bot will accept unauthenticated requests on #{@messaging_endpoint}."
        )
      else
        logger&.warn(
          "No credentials configured and dangerously_allow_unauthenticated_requests is not enabled. " \
          "All incoming requests will be rejected. Configure client authentication to securely receive " \
          "messages, or set dangerously_allow_unauthenticated_requests: true for local development."
        )
      end
    end

    # Token dispatch for scoped API clients: no identity uses the app
    # token; an identity with an agentic user uses the agentic user token;
    # otherwise the agentic app token. Kinds never fall back to each other -
    # failing is safer than authenticating under the wrong identity.
    def token_for_agentic_identity(identity)
      return @token_manager.bot_token unless identity

      if identity.agentic_user_id
        @token_manager.agentic_user_token(
          @cloud.agent_bot_scope,
          agentic_app_id: identity.agentic_app_id,
          agentic_user_id: identity.agentic_user_id,
          tenant_id: identity.tenant_id
        )
      else
        @token_manager.agentic_app_token(
          @cloud.agent_bot_scope,
          agentic_app_id: identity.agentic_app_id,
          tenant_id: identity.tenant_id
        )
      end
    end

    def validate_inbound!(env, activity)
      return if @dangerously_allow_unauthenticated_requests

      raise AuthenticationError, "CLIENT_ID is required for inbound validation" unless @jwt_validator

      @jwt_validator.validate_inbound_activity!(env["HTTP_AUTHORIZATION"], service_url: activity.service_url)
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
