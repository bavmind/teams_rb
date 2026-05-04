# frozen_string_literal: true

require_relative "test_helper"

class ActivityModelsTest < Minitest::Test
  def test_activity_exposes_explicit_account_models
    activity = Teams::Activity.new(teams_payload)

    assert_instance_of Teams::Api::Account, activity.from
    assert_equal "user-1", activity.from.id
    assert_equal "aad-1", activity.from.aad_object_id
    refute_respond_to activity.from, :aadObjectId
  end

  def test_activity_exposes_explicit_conversation_model
    activity = Teams::Activity.new(
      teams_payload.merge(
        "conversation" => {
          "id" => "conversation-1",
          "tenantId" => "tenant-1",
          "conversationType" => "personal"
        }
      )
    )

    assert_instance_of Teams::Api::ConversationAccount, activity.conversation
    assert_equal "conversation-1", activity.conversation.id
    assert_equal "tenant-1", activity.conversation.tenant_id
    assert_equal "personal", activity.conversation.conversation_type
    refute_respond_to activity.conversation, :conversationType
  end

  def test_activity_exposes_channel_data_model
    activity = Teams::Activity.new(
      teams_payload.merge(
        "channelData" => {
          "tenant" => { "id" => "tenant-1" },
          "team" => { "id" => "team-1", "teamType" => "standard" },
          "channel" => { "id" => "channel-1", "type" => "standard" },
          "notification" => { "alertInMeeting" => true },
          "streamType" => "informative"
        }
      )
    )

    assert_instance_of Teams::Api::ChannelData, activity.channel_data
    assert_instance_of Teams::Api::TenantInfo, activity.channel_data.tenant
    assert_equal "tenant-1", activity.channel_data.tenant.id
    assert_instance_of Teams::Api::TeamInfo, activity.channel_data.team
    assert_equal "standard", activity.channel_data.team.team_type
    assert_instance_of Teams::Api::ChannelInfo, activity.channel_data.channel
    assert_equal "standard", activity.channel_data.channel.type
    assert_instance_of Teams::Api::NotificationInfo, activity.channel_data.notification
    assert_equal true, activity.channel_data.notification.alert_in_meeting
    assert_equal "informative", activity.channel_data.stream_type
    refute_respond_to activity.channel_data, :streamType
  end

  def test_activity_value_uses_explicit_model_when_hash
    activity = Teams::Activity.new(teams_payload.merge("value" => { "action" => "save" }))

    assert_instance_of Teams::Api::ActivityValue, activity.value
    assert_equal({ "action" => "save" }, activity.value.to_h)
  end

  def test_account_serializes_to_teams_keys
    account = Teams::Api::Account.new(
      id: "user-1",
      name: "User One",
      aad_object_id: "aad-1",
      user_principal_name: "user@example.com"
    )

    assert_equal(
      {
        "id" => "user-1",
        "name" => "User One",
        "aadObjectId" => "aad-1",
        "userPrincipalName" => "user@example.com"
      },
      account.to_h
    )
  end
end
