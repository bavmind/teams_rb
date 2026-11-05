# frozen_string_literal: true

require "base64"
require "json"

module Teams
  class ActivityContext
    # Typed messages, edits, deletes, and reactions carry plain numeric
    # message ids; invokes and card-button messages carry service-generated
    # ids such as "f:<guid>", which the service rejects as quote targets.
    NUMERIC_MESSAGE_ID = /\A0*[1-9][0-9]*\z/

    # state is the turn's State::TurnStateContainer (ctx.state.conversation,
    # ctx.state.user), or nil when the app was built without state:.
    attr_reader :app, :activity, :conversation_reference, :extra, :stream, :state

    def initialize(app:, activity:, conversation_reference:, extra: {}, stream: nil, api: nil, files_credential: nil,
      files_bot_api_credential: nil, state: nil)
      @app = app
      @activity = activity
      @conversation_reference = conversation_reference
      @extra = extra
      @stream = stream
      @api = api
      @files_credential = files_credential
      @files_bot_api_credential = files_bot_api_credential
      @state = state
    end

    def ref
      conversation_reference
    end

    def reference
      conversation_reference
    end

    def log
      app.logger
    end

    def storage
      app.storage
    end

    # The turn's API client; scoped to the activity's agentic identity when
    # the app runs as an Agent 365 agent.
    def api
      @api || app.api
    end

    # The uploaded files and pasted inline images on the inbound activity, as
    # Files::IncomingFile handles. See Files::FilesAccessor.
    def files
      @files ||= Files::FilesAccessor.new(
        activity,
        downloader: app.files_downloader,
        credential: @files_credential,
        bot_api_credential: @files_bot_api_credential,
        logger: log
      )
    end

    # The TypeScript, Python, and .NET SDKs call this operation `send`.
    # Ruby already defines Object#send for dynamic dispatch, so the public
    # Ruby API uses `post` to avoid shadowing a core language method.
    def post(activity_or_text)
      app.send_activity(conversation_reference, apply_targeted_defaults(activity_or_text), api:)
    end

    # Quotes the inbound message only when its id is a plain numeric message
    # id (digits, not all zeros), like the TypeScript, Python, and .NET SDKs;
    # otherwise sends exactly like post. Use quote to quote a specific id.
    def reply(activity_or_text)
      return post(activity_or_text) unless NUMERIC_MESSAGE_ID.match?(activity.id.to_s)
      # Replies to targeted inbound messages are targeted sends: no quoted
      # reply and no replyToId, matching the TypeScript and Python SDKs.
      return post(activity_or_text) if targeted_reply?(activity_or_text)

      quote(activity.id, activity_or_text)
    end

    # Quoted replies are plain sends carrying the quote placeholder and
    # entity, matching the TypeScript and Python SDKs; no replyToId is set.
    def quote(message_id, activity_or_text)
      post(quoted_activity(message_id, activity_or_text))
    end

    # Sugar over post: the SDKs update by sending an activity that already
    # carries an id, and post does exactly that. See AGENTS.md.
    def update(activity_id, activity_or_text)
      post(activity_with_id(activity_id, activity_or_text))
    end

    def typing(text = nil)
      post(Api::TypingActivity.new(text))
    end

    # Microsoft Graph client with the app's own identity (app-only tokens).
    def app_graph
      app.graph
    end

    # Microsoft Graph client with the signed-in user's token. Raises when
    # the user is not signed in, like the Python SDK's user_graph.
    def user_graph(connection_name: nil)
      connection = connection_name || app.default_connection_name
      @user_graph ||= {}
      @user_graph[connection] ||= begin
        response = api.users.get_token(
          user_id: activity.from.id,
          connection_name: connection,
          channel_id: activity.channel_id
        )
        raise Error, "User must be signed in to access the Graph client" if response.token.to_s.empty?

        Graph::Client.new(token: response.token, base_url_root: app.graph.base_url_root)
      rescue HttpError
        raise Error, "User must be signed in to access the Graph client"
      end
    end

    # Starts the user sign-in flow: returns the token if the user is already
    # signed in, otherwise sends an OAuth card and returns nil. In group
    # chats and channels the card is a targeted message visible only to the
    # requesting user; channels omit the token exchange resource because
    # channel scope cannot do the silent SSO exchange, so the card renders
    # the sign-in button instead.
    def sign_in(connection_name: nil, oauth_card_text: "Please Sign In...", sign_in_button_text: "Sign In")
      connection_name ||= app.default_connection_name

      connection_name = OAuth.normalize_connection_name(connection_name)

      token = get_user_token(connection_name:)
      return token if token && !token.to_s.empty?

      state = Base64.strict_encode64(JSON.generate(
        "connectionName" => connection_name,
        "conversation" => conversation_reference.to_h,
        "msAppId" => app.client_id
      ))
      resource = api.bots.sign_in.get_resource(state:)

      is_channel = activity.conversation.conversation_type == "channel"
      recipient = activity.from.to_h
      recipient = recipient.merge("isTargeted" => true) if activity.conversation.is_group

      card = {
        "text" => oauth_card_text,
        "connectionName" => connection_name,
        "tokenExchangeResource" => (resource.token_exchange_resource&.to_h unless is_channel),
        "tokenPostResource" => resource.token_post_resource&.to_h,
        "buttons" => [
          { "type" => "signin", "title" => sign_in_button_text, "value" => resource.sign_in_link }
        ]
      }.compact

      payload = {
        "type" => "message",
        "recipient" => recipient,
        "attachments" => [
          { "contentType" => "application/vnd.microsoft.card.oauth", "content" => card }
        ]
      }

      send_sign_in_card(payload, connection_name, sso_offered: card.key?("tokenExchangeResource"))
      nil
    end

    # The user's token for a connection (default: the app's default
    # connection), or nil when not signed in. Only the Token Service's 404
    # means "not signed in"; other failures raise, so an outage is never
    # mistaken for a signed-out user. Prefer app.get_oauth_flow(name).get_token
    # with registered flows.
    def get_user_token(connection_name: nil)
      api.users.get_token(
        user_id: activity.from.id,
        connection_name: connection_name || app.default_connection_name,
        channel_id: activity.channel_id
      ).token
    rescue HttpError => error
      raise unless error.status == 404

      nil
    end

    # Token status for every OAuth connection on the bot in one Token Service
    # call. The bulk call can lag a fresh sign-in or omit a connection, so a
    # registered flow reported missing or without a token is re-checked with
    # a direct lookup, like the Python SDK.
    def get_connection_status
      statuses = api.users.get_token_status(user_id: activity.from.id, channel_id: activity.channel_id)
      registered = app.oauth_registry.each_with_object({}) do |flow, names|
        names[OAuth.lookup_key(flow.connection_name)] = flow.connection_name
      end
      return statuses if registered.empty?

      resolved = Set.new
      corrected = statuses.map do |status|
        key = OAuth.lookup_key(status.connection_name)
        resolved << key if key
        next status if key.nil? || !registered.key?(key) || status.has_token

        get_user_token(connection_name: registered[key]) ? Api::TokenStatus.new(status.to_h.merge("hasToken" => true)) : status
      end

      registered.each do |key, name|
        next if resolved.include?(key)

        corrected << Api::TokenStatus.new(
          "channelId" => activity.channel_id,
          "connectionName" => name,
          "hasToken" => !get_user_token(connection_name: name).nil?,
          "serviceProviderDisplayName" => ""
        )
      end
      corrected
    end

    # Clears the user's token for the connection. Failures are logged, not
    # raised, matching the TypeScript/Python SDKs.
    def sign_out(connection_name: nil)
      api.users.sign_out(
        user_id: activity.from.id,
        connection_name: connection_name || app.default_connection_name,
        channel_id: activity.channel_id
      )
      nil
    rescue HttpError => error
      log&.error("Failed to sign out user: #{error.message}")
      nil
    end

    private

    # Records which connection the sign-in started on, so the connection-less
    # verify-state and failure callbacks can be routed to its flow, then sends
    # the card. With state the record is saved right away; if the card cannot
    # be sent, the previous records are restored so they cannot mis-route a
    # later callback.
    def send_sign_in_card(payload, connection_name, sso_offered:)
      cache = app.oauth_pending_cache
      scope = { conversation_id: activity.conversation&.id, user_id: activity.from&.id }
      previous = OAuth::PendingSignIns.list(state, cache, **scope)
      begin
        OAuth::PendingSignIns.record(state, cache, connection_name, sso_offered:, **scope)
        state&.save
        app.send_activity(conversation_reference, payload, api:)
      rescue StandardError
        begin
          OAuth::PendingSignIns.replace(state, cache, previous, **scope)
          if state
            state.user&.mark_dirty
            state.save
          end
        rescue StandardError => rollback_error
          log&.warn(
            "Failed to roll back pending OAuth sign-in state for connection '#{connection_name}': " \
            "#{rollback_error.message}"
          )
        end
        raise
      end
    end

    def incoming_targeted_sender
      return nil unless activity.message?
      return nil unless activity.recipient.is_targeted == true

      activity.from
    end

    def apply_targeted_defaults(activity_or_text)
      sender = incoming_targeted_sender
      return activity_or_text unless sender

      body = activity_body(activity_or_text)
      return activity_or_text unless body

      if body["type"] == "message" && !body["id"] && !body.key?("recipient")
        body["recipient"] = sender.to_h.merge("isTargeted" => true)
      end

      return body unless targeted_outbound?(body)

      add_targeted_message_info(body, activity.id)
      body
    end

    def targeted_reply?(activity_or_text)
      return false unless incoming_targeted_sender

      body = activity_body(activity_or_text)
      return false unless body
      return false unless body["type"] == "message"

      (!body["id"] && !body.key?("recipient")) || targeted_outbound?(body)
    end

    def targeted_outbound?(body)
      body["type"] == "message" && body.dig("recipient", "isTargeted") == true
    end

    def activity_body(activity_or_text)
      outbound = normalize_activity(activity_or_text)
      body = outbound.respond_to?(:to_h) ? outbound.to_h : outbound
      body.is_a?(Hash) ? body.dup : nil
    end

    # Hash counterpart of MessageActivity#add_targeted_message_info: strips
    # quotedReply artifacts and adds the prompt preview entity once.
    def add_targeted_message_info(body, message_id)
      entities = Array(body["entities"]).reject do |entity|
        entity.is_a?(Hash) && entity["type"] == "quotedReply"
      end
      body["text"] = body["text"].gsub(%(<quoted messageId="#{message_id}"/>), "").strip if body["text"]

      unless entities.any? { |entity| entity.is_a?(Hash) && entity["type"] == "targetedMessageInfo" }
        entities << { "type" => "targetedMessageInfo", "messageId" => message_id }
      end

      body["entities"] = entities
    end

    def activity_with_id(activity_id, activity_or_text)
      outbound = normalize_activity(activity_or_text)
      body = outbound.respond_to?(:to_h) ? outbound.to_h : outbound
      body.merge("id" => activity_id)
    end

    def quoted_activity(message_id, activity_or_text)
      outbound = normalize_activity(activity_or_text)
      return outbound.prepend_quote(message_id) if outbound.is_a?(Api::MessageActivity)

      body = outbound.respond_to?(:to_h) ? outbound.to_h : outbound
      return body unless body.is_a?(Hash)

      body = body.dup
      prepend_quote_to_hash(body, message_id) if body["type"] == "message"
      body
    end

    def prepend_quote_to_hash(body, message_id)
      body["entities"] = Array(body["entities"]) + [
        Api::QuotedReplyEntity.new("quotedReply" => { "messageId" => message_id }).to_h
      ]
      placeholder = %(<quoted messageId="#{message_id}"/>)
      body["text"] = body["text"].to_s.strip.empty? ? placeholder : "#{placeholder} #{body["text"]}"
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
  end
end
