# frozen_string_literal: true

require_relative "teams/version"
require_relative "teams/errors"
require_relative "teams/cloud_environment"
require_relative "teams/cards"
require_relative "teams/cards/generated"
require_relative "teams/api/model"
require_relative "teams/api/account"
require_relative "teams/api/conversation_account"
require_relative "teams/api/tenant_info"
require_relative "teams/api/team_info"
require_relative "teams/api/channel_info"
require_relative "teams/api/notification_info"
require_relative "teams/api/meeting_info"
require_relative "teams/api/channel_data"
require_relative "teams/api/activity_value"
require_relative "teams/api/quoted_reply_entity"
require_relative "teams/api/sent_activity"
require_relative "teams/api/citation_appearance"
require_relative "teams/activity"
require_relative "teams/activity_context"
require_relative "teams/http_stream"
require_relative "teams/router"
require_relative "teams/response"
require_relative "teams/storage/memory_store"
require_relative "teams/common/http_client"
require_relative "teams/api/conversation_reference"
require_relative "teams/auth/client_secret_credentials"
require_relative "teams/auth/token"
require_relative "teams/auth/token_manager"
require_relative "teams/auth/jwt_validator"
require_relative "teams/api/reaction_client"
require_relative "teams/api/client"
require_relative "teams/api/message_activity"
require_relative "teams/api/typing_activity"
require_relative "teams/rack_app"
require_relative "teams/app"

module Teams
  # Constructs a threaded conversation ID by appending ";messageid={message_id}",
  # the format the Teams service uses to route messages to a specific thread.
  def self.to_threaded_conversation_id(conversation_id, message_id)
    raise ArgumentError, "conversation_id must be a non-empty String" if conversation_id.to_s.empty?

    message_id = message_id.to_s
    unless message_id.match?(/\A\d+\z/) && message_id != "0"
      raise ArgumentError, %(invalid message_id "#{message_id}": must be a non-zero numeric value)
    end

    "#{conversation_id.split(";").first};messageid=#{message_id}"
  end
end
