# frozen_string_literal: true

require "logger"

module Teams
  class App
    DEFAULT_MESSAGING_ENDPOINT = "/api/messages"

    attr_reader :api, :logger, :storage, :messaging_endpoint, :default_connection_name, :graph

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
      @sign_in_handlers = []
      @error_handlers = []
      @functions = {}
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

      # Graph base URL derives from the cloud's graph scope host (sovereign
      # clouds), like the TypeScript SDK; the app-identity client requests
      # app-only tokens through the client-credentials flow.
      graph_root = cloud.graph_scope.to_s[%r{\Ahttps?://[^/]+}]
      @graph = Graph::Client.new(
        token: -> { @token_manager.token_for(cloud.graph_scope, @token_manager.credentials&.tenant_id || cloud.login_tenant) },
        base_url_root: graph_root
      )

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
    # fire on_sign_in / on_error; handlers registered here run after them.
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

    # Called with (ctx, token_response) whenever a sign-in completes through
    # the default token-exchange or verify-state handlers.
    def on_sign_in(&block)
      @sign_in_handlers << block
      self
    end

    # Called with (error, activity) when a default OAuth handler hits an
    # unexpected failure or the Teams client reports a sign-in failure.
    def on_error(&block)
      @error_handlers << block
      self
    end

    def emit_sign_in(context, token_response)
      @sign_in_handlers.each { |handler| handler.call(context, token_response) }
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

    # Default OAuth handlers, mirroring the TypeScript/Python OauthHandlers:
    # registered first on the signin routes, they complete the flows, fire
    # the sign-in/error events, and chain to user handlers via next. Their
    # return value is the invoke response; 412 tells the Teams client to
    # fall back to the interactive card flow.
    def register_default_oauth_handlers
      app = self

      @router.on_signin_token_exchange do |ctx, nxt|
        value = ctx.activity.value
        begin
          if value.raw["connectionName"] != app.default_connection_name
            app.logger&.warn(
              "Sign-in token exchange invoked with connection name #{value.raw["connectionName"].inspect}, " \
              "but the default connection name is #{app.default_connection_name.inspect}. " \
              "Token verification will likely fail."
            )
          end

          begin
            token = ctx.api.users.exchange_token(
              user_id: ctx.activity.from.id,
              connection_name: value.raw["connectionName"],
              channel_id: ctx.activity.channel_id,
              exchange_request: { "token" => value.raw["token"] }
            )
            app.emit_sign_in(ctx, token)
            nil
          rescue HttpError => error
            unless [404, 400, 412].include?(error.status)
              app.logger&.error("Error exchanging token: #{error.message}")
              app.emit_error(error, activity: ctx.activity)
              next Response.new(status: error.status || 500)
            end

            Response.new(
              status: 412,
              body: {
                "id" => value.raw["id"],
                "connectionName" => value.raw["connectionName"],
                "failureDetail" => error.message
              }
            )
          end
        ensure
          nxt.call
        end
      end

      @router.on_signin_verify_state do |ctx, nxt|
        begin
          state = ctx.activity.value.raw["state"]
          if state.to_s.empty?
            app.logger&.warn("Auth state not present on signin/verifyState invoke")
            next Response.new(status: 404)
          end

          begin
            token = ctx.api.users.get_token(
              user_id: ctx.activity.from.id,
              connection_name: app.default_connection_name,
              channel_id: ctx.activity.channel_id,
              code: state
            )
            app.emit_sign_in(ctx, token)
            nil
          rescue HttpError => error
            app.logger&.error("Error verifying sign-in state: #{error.message}")
            unless [404, 400, 412].include?(error.status)
              app.emit_error(error, activity: ctx.activity)
              next Response.new(status: error.status || 500)
            end

            Response.new(status: 412)
          end
        ensure
          nxt.call
        end
      end

      @router.on_signin_failure do |ctx, nxt|
        begin
          value = ctx.activity.value
          app.logger&.warn(
            "Sign-in failed: #{value.raw["code"]} - #{value.raw["message"]}. " \
            "If the code is 'resourcematchfailed', verify the Entra app registration's " \
            "Application ID URI matches the OAuth connection's Token Exchange URL."
          )
          app.emit_error(
            Error.new("Sign-in failure: #{value.raw["code"]} - #{value.raw["message"]}"),
            activity: ctx.activity
          )
          nil
        ensure
          nxt.call
        end
      end
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
