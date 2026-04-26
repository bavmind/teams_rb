# frozen_string_literal: true

require_relative "test_helper"

class ConversationReferenceTest < Minitest::Test
  def test_builds_from_activity
    activity = Teams::Activity.new(
      teams_payload.merge(
        "locale" => "en-US",
        "conversation" => { "id" => "conversation-1", "conversationType" => "personal" }
      )
    )

    reference = Teams::Api::ConversationReference.from_activity(activity)

    assert_equal "activity-1", reference.activity_id
    assert_equal "user-1", reference.user.id
    assert_equal "bot-1", reference.bot.id
    assert_equal "conversation-1", reference.conversation_id
    assert_equal "personal", reference.conversation.conversation_type
    assert_equal "msteams", reference.channel_id
    assert_equal "en-US", reference.locale
    assert_equal "https://smba.trafficmanager.net/teams", reference.service_url
  end

  def test_serializes_to_teams_shape
    reference = Teams::Api::ConversationReference.new(
      activity_id: "activity-1",
      user: { "id" => "user-1" },
      locale: "en-US",
      bot: { "id" => "bot-1", "role" => "bot" },
      conversation: { "id" => "conversation-1" },
      channel_id: "msteams",
      service_url: "https://smba.trafficmanager.net/teams"
    )

    assert_equal(
      {
        "activityId" => "activity-1",
        "user" => { "id" => "user-1" },
        "locale" => "en-US",
        "bot" => { "id" => "bot-1", "role" => "bot" },
        "conversation" => { "id" => "conversation-1" },
        "channelId" => "msteams",
        "serviceUrl" => "https://smba.trafficmanager.net/teams"
      },
      reference.to_h
    )
  end

  def test_round_trips_from_hash
    raw = {
      "activityId" => "activity-1",
      "user" => { "id" => "user-1" },
      "locale" => "en-US",
      "bot" => { "id" => "bot-1" },
      "conversation" => { "id" => "conversation-1" },
      "channelId" => "msteams",
      "serviceUrl" => "https://smba.trafficmanager.net/teams"
    }

    reference = Teams::Api::ConversationReference.from_h(raw)

    assert_equal raw, reference.to_h
    assert_equal raw, JSON.parse(reference.to_json)
  end

  def test_from_h_accepts_symbol_keys
    reference = Teams::Api::ConversationReference.from_h(
      bot: { id: "bot-1" },
      conversation: { id: "conversation-1" },
      channel_id: "msteams",
      service_url: "https://smba.trafficmanager.net/teams"
    )

    assert_equal "bot-1", reference.bot.id
    assert_equal "conversation-1", reference.conversation_id
    assert_equal "msteams", reference.channel_id
    assert_equal "https://smba.trafficmanager.net/teams", reference.service_url
  end
end
