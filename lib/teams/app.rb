# frozen_string_literal: true

require "logger"

module Teams
  class App
    DEFAULT_MESSAGING_ENDPOINT = "/api/messages"

    attr_reader :api, :logger, :storage, :messaging_endpoint

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
      additional_allowed_domains: [],
      skip_service_url_validation: false,
      messaging_endpoint: DEFAULT_MESSAGING_ENDPOINT
    )
      @logger = logger
      @storage = storage
      @cloud = cloud
      @skip_auth = skip_auth
      @skip_service_url_validation = skip_service_url_validation
      @messaging_endpoint = normalize_messaging_endpoint(messaging_endpoint)
      @router = Router.new

      @token_manager = token_manager || Auth::TokenManager.from_env(client_id:, client_secret:, tenant_id:, cloud:)
      @api = api || Api::Client.new(
        service_url:,
        http: Common::HttpClient.new(token: -> { @token_manager.bot_token }),
        logger:
      )
      @jwt_validator = Auth::JwtValidator.new(
        client_id: @token_manager.client_id,
        tenant_id: @token_manager.credentials&.tenant_id,
        cloud:
      ) if @token_manager.client_id
      @service_url_validator = Auth::ServiceUrlValidator.new(cloud:, additional_allowed_domains:)
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

    def process_inbound(payload, env: {})
      activity = Activity.new(payload)
      validate_inbound!(env, activity)
      validate_service_url!(activity)

      conversation_reference = Api::ConversationReference.from_activity(activity)
      context = ActivityContext.new(
        app: self,
        activity:,
        conversation_reference:,
        stream: HttpStream.new(app: self, conversation_reference:)
      )
      result = run_handlers(context)
      context.stream.close

      result.is_a?(Response) ? result : Response.new(status: 200)
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

    def reply(conversation_id, activity_id_or_activity, activity_or_text = nil, service_url: nil)
      assert_string!(conversation_id, "conversation_id")

      if activity_or_text
        assert_string!(activity_id_or_activity, "activity_id")

        reply_to_activity(
          proactive_reference(conversation_id, service_url:),
          activity_id_or_activity,
          activity_or_text
        )
      else
        post(conversation_id, activity_id_or_activity, service_url:)
      end
    end

    def send_activity(conversation_reference, activity_or_text)
      api.send_to_conversation(
        conversation_reference.conversation_id,
        activity_for_reference(conversation_reference, activity_or_text),
        service_url: conversation_reference.service_url
      )
    end

    def reply_to_activity(conversation_reference, activity_id, activity_or_text)
      activity = activity_for_reference(conversation_reference, activity_or_text)
      activity["replyToId"] ||= activity_id if activity.is_a?(Hash) && activity_id

      api.send_to_conversation(
        conversation_reference.conversation_id,
        activity,
        service_url: conversation_reference.service_url
      )
    end

    private

    def validate_inbound!(env, activity)
      return if @skip_auth

      raise AuthenticationError, "CLIENT_ID is required for inbound validation" unless @jwt_validator

      @jwt_validator.validate!(env["HTTP_AUTHORIZATION"], service_url: activity.service_url)
    end

    def validate_service_url!(activity)
      return if @skip_service_url_validation

      @service_url_validator.validate!(activity.service_url)
    end

    def run_handlers(context)
      routes = @router.matching(context.activity)
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

    def activity_for_reference(conversation_reference, activity_or_text)
      activity = normalize_activity(activity_or_text)
      body = activity.respond_to?(:to_h) ? activity.to_h : activity
      return body unless body.is_a?(Hash)

      body = body.dup
      body["from"] ||= conversation_reference.bot.to_h if conversation_reference.bot
      body["recipient"] ||= conversation_reference.user.to_h if conversation_reference.user
      body["conversation"] ||= conversation_reference.conversation.to_h
      body["channelId"] ||= conversation_reference.channel_id if conversation_reference.channel_id
      body["locale"] ||= conversation_reference.locale if conversation_reference.locale
      body
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
        activity_or_text
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
