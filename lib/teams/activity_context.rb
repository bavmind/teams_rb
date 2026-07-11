# frozen_string_literal: true

require "base64"
require "json"

module Teams
  class ActivityContext
    attr_reader :app, :activity, :conversation_reference, :extra, :stream

    def initialize(app:, activity:, conversation_reference:, extra: {}, stream: nil)
      @app = app
      @activity = activity
      @conversation_reference = conversation_reference
      @extra = extra
      @stream = stream
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

    def api
      app.api
    end

    # The TypeScript, Python, and .NET SDKs call this operation `send`.
    # Ruby already defines Object#send for dynamic dispatch, so the public
    # Ruby API uses `post` to avoid shadowing a core language method.
    def post(activity_or_text)
      app.send_activity(conversation_reference, apply_targeted_defaults(activity_or_text))
    end

    def reply(activity_or_text)
      return post(activity_or_text) unless activity.id
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
      @user_graph ||= begin
        response = api.users.get_token(
          user_id: activity.from.id,
          connection_name: connection_name || app.default_connection_name,
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
    # conversations the card goes to a 1:1 conversation with the user (group
    # OAuth is not supported by Teams), like the TypeScript/Python SDKs.
    def sign_in(connection_name: nil, oauth_card_text: "Please Sign In...", sign_in_button_text: "Sign In")
      connection_name ||= app.default_connection_name

      begin
        response = api.users.get_token(
          user_id: activity.from.id,
          connection_name:,
          channel_id: activity.channel_id
        )
        return response.token if response.token && !response.token.to_s.empty?
      rescue HttpError
        # No token yet; continue with the OAuth card flow.
      end

      conversation_id = conversation_reference.conversation_id
      if activity.conversation.is_group
        one_on_one = api.conversations.create(
          members: [activity.from.to_h],
          tenant_id: activity.conversation.tenant_id
        )
        conversation_id = one_on_one.id
        post(oauth_card_text)
      end

      state = Base64.strict_encode64(JSON.generate(
        "connectionName" => connection_name,
        "conversation" => conversation_reference.to_h,
        "msAppId" => app.client_id
      ))
      resource = api.bots.sign_in.get_resource(state:)

      card = {
        "text" => oauth_card_text,
        "connectionName" => connection_name,
        "tokenExchangeResource" => resource.token_exchange_resource&.to_h,
        "tokenPostResource" => resource.token_post_resource&.to_h,
        "buttons" => [
          { "type" => "signin", "title" => sign_in_button_text, "value" => resource.sign_in_link }
        ]
      }.compact

      payload = {
        "type" => "message",
        "recipient" => activity.from.to_h,
        "attachments" => [
          { "contentType" => "application/vnd.microsoft.card.oauth", "content" => card }
        ]
      }

      app.send_activity(sign_in_reference(conversation_id), payload)
      nil
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

    def sign_in_reference(conversation_id)
      return conversation_reference if conversation_id == conversation_reference.conversation_id

      Api::ConversationReference.from_h(
        conversation_reference.to_h.merge(
          "conversation" => conversation_reference.conversation.to_h.merge("id" => conversation_id)
        )
      )
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
