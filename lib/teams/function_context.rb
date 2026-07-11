# frozen_string_literal: true

module Teams
  # Context for a remote function call from a tab (POST /api/functions/{name}):
  # the validated Entra identity, the Teams client context headers, and the
  # request payload.
  class FunctionContext
    attr_reader :app, :function_name, :data, :app_session_id, :page_id, :auth_token,
      :tenant_id, :user_id, :user_name, :app_id, :channel_id, :chat_id,
      :meeting_id, :message_id, :sub_page_id, :team_id

    def initialize(app:, function_name:, data:, app_session_id:, page_id:, auth_token:,
                   tenant_id:, user_id:, user_name:, app_id: nil, channel_id: nil,
                   chat_id: nil, meeting_id: nil, message_id: nil, sub_page_id: nil, team_id: nil)
      @app = app
      @function_name = function_name
      @data = data
      @app_session_id = app_session_id
      @page_id = page_id
      @auth_token = auth_token
      @tenant_id = tenant_id
      @user_id = user_id
      @user_name = user_name
      @app_id = app_id
      @channel_id = channel_id
      @chat_id = chat_id
      @meeting_id = meeting_id
      @message_id = message_id
      @sub_page_id = sub_page_id
      @team_id = team_id
      @resolved = false
    end

    def api
      app.api
    end

    def log
      app.logger
    end

    # Resolves the conversation this call relates to, like the TypeScript and
    # Python function contexts: chat/channel id when the user is a member of
    # it; in personal scope, creates (or re-fetches) the 1:1 conversation.
    # Returns nil when no conversation can be resolved.
    def conversation_id
      return @conversation_id if @resolved

      @resolved = true
      @conversation_id = resolve_conversation_id
    end

    # Posts into the resolved conversation (proactive send with the bot's
    # identity).
    def post(activity_or_text)
      id = conversation_id
      raise Error, "Unable to resolve a conversation for this function call" unless id

      app.post(id, activity_or_text)
    end

    private

    def resolve_conversation_id
      existing = chat_id || channel_id

      if existing.nil?
        conversation = api.conversations.create(
          members: [{ "id" => user_id, "role" => "user", "name" => user_name }],
          tenant_id: tenant_id
        )
        return conversation.id
      end

      member = api.conversations.get_member_by_id(existing, user_id)
      member ? existing : nil
    rescue HttpError => error
      log&.warn("Could not resolve conversation for function call: #{error.message}")
      nil
    end
  end
end
