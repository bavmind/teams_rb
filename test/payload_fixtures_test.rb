# frozen_string_literal: true

require_relative "test_helper"

# Sanitized real Teams wire payloads, captured live 2026-07-11 through Dev
# Tunnel. They preserve wire details synthetic payloads miss: regional
# service URLs, clientInfo entities, channelData source/legacy fields, and
# ephemeral f:-prefixed invoke ids.
class PayloadFixturesTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures/payloads", __dir__)

  def test_message_payload
    activity = load_activity("message")

    assert activity.message?
    assert_equal "hi teams", activity.text
    assert_equal "Test User", activity.from.name
    assert_equal "00000000-0000-0000-0000-00000000aaaa", activity.from.aad_object_id
    assert_equal "personal", activity.conversation.conversation_type
    assert_equal "https://smba.trafficmanager.net/de/00000000-0000-0000-0000-0000000000ff/", activity.service_url

    reference = Teams::Api::ConversationReference.from_activity(activity)
    assert_equal "a:1sanitizedConversationId", reference.conversation_id
  end

  def test_message_edit_payload
    activity = load_activity("message_edit")

    assert activity.message_update?
    assert_equal "editMessage", activity.channel_data.event_type
    assert_equal "hello world", activity.text

    router = Teams::Router.new
    router.on_edit_message { nil }
    assert_equal 1, router.matching(activity).length
  end

  def test_message_reaction_payload
    activity = load_activity("message_reaction")

    assert_equal "messageReaction", activity.type
    assert_equal "like", activity.raw["reactionsAdded"].first["type"]
    refute activity.message?
  end

  def test_task_fetch_invoke_payload
    activity = load_activity("invoke_task_fetch")

    assert activity.invoke?
    assert_equal "task/fetch", activity.name
    # Teams unwraps the card action's msteams wrapper into value.data.
    assert_equal "simple_form", activity.value.data["dialog_id"]
    assert activity.id.start_with?("f:"), "invoke ids are ephemeral f:-prefixed"

    router = Teams::Router.new
    router.on_dialog_open("simple_form") { nil }
    router.on_dialog_open("other") { nil }
    assert_equal 1, router.matching(activity).length
  end

  def test_task_submit_invoke_payload
    activity = load_activity("invoke_task_submit")

    assert activity.invoke?
    assert_equal "task/submit", activity.name
    assert_equal "submit_simple_form", activity.value.data["action"]
    assert_equal "Test", activity.value.data["name"]

    router = Teams::Router.new
    router.on_dialog_submit("submit_simple_form") { nil }
    router.on_dialog_submit("other") { nil }
    assert_equal 1, router.matching(activity).length
  end

  def test_card_submit_message_payload
    activity = load_activity("message_card_submit")

    assert activity.message?
    # Card Action.Submit arrives as a message with no text and the inputs in
    # value; answer it with post, never reply.
    assert_nil activity.text
    assert_equal "create", activity.raw.dig("value", "action")
    assert_equal "42", activity.raw.dig("value", "amount")
  end

  private

  def load_activity(name)
    Teams::Activity.new(JSON.parse(File.read(File.join(FIXTURES, "#{name}.json"))))
  end
end
