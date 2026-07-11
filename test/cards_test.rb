# frozen_string_literal: true

require_relative "test_helper"

# Serialization exactness against the Python SDK is covered by the golden
# corpus in cards_generated_test.rb; this file covers the Ruby conveniences
# and integration with message activities.
class CardsTest < Minitest::Test
  def test_adaptive_card_serializes_core_elements_and_actions
    card = Teams::Cards::AdaptiveCard.new(
      Teams::Cards::TextBlock.new("Create ticket", weight: "Bolder", size: "Large", wrap: true),
      Teams::Cards::TextInput.new(
        id: "title",
        label: "Title",
        placeholder: "Short summary",
        is_required: true,
        error_message: "Title is required"
      ),
      Teams::Cards::ChoiceSetInput.new(
        Teams::Cards::Choice.new(title: "Bug", value: "bug"),
        Teams::Cards::Choice.new(title: "Question", value: "question"),
        id: "kind",
        label: "Kind",
        style: "expanded"
      ),
      actions: [
        Teams::Cards::SubmitAction.new(title: "Create", data: { action: "create_ticket" }),
        Teams::Cards::OpenUrlAction.new("https://example.com/help", title: "Help")
      ]
    )

    body = card.to_h

    assert_equal "AdaptiveCard", body["type"]
    assert_equal "1.5", body["version"]
    assert_equal %w[TextBlock Input.Text Input.ChoiceSet], body["body"].map { |item| item["type"] }

    text_block = body["body"][0]
    assert_equal "Create ticket", text_block["text"]
    assert_equal "Bolder", text_block["weight"]

    input = body["body"][1]
    assert_equal "title", input["id"]
    assert_equal true, input["isRequired"]
    assert_equal "Title is required", input["errorMessage"]

    choices = body["body"][2]["choices"]
    assert_equal [%w[Bug bug], %w[Question question]], choices.map { |c| [c["title"], c["value"]] }

    submit, open_url = body["actions"]
    assert_equal "Action.Submit", submit["type"]
    assert_equal({ "action" => "create_ticket" }, submit["data"])
    assert_equal "Action.OpenUrl", open_url["type"]
    assert_equal "https://example.com/help", open_url["url"]
  end

  def test_card_builder_methods
    card = Teams::Cards::AdaptiveCard.new
      .add_item(Teams::Cards::TextBlock.new("Status").with_text("Updated status"))
      .add_action(Teams::Cards::ExecuteAction.new(title: "Refresh").with_verb("refresh"))
      .with_fallback_text("Fallback")

    assert_equal "Updated status", card.to_h.fetch("body").first.fetch("text")
    assert_equal "Fallback", card.to_h.fetch("fallbackText")

    action = card.to_h.fetch("actions").first
    assert_equal "Action.Execute", action["type"]
    assert_equal "Refresh", action["title"]
    assert_equal "refresh", action["verb"]
  end

  def test_schema_field_and_extra_options
    card = Teams::Cards::AdaptiveCard.new(
      ac_schema: "http://adaptivecards.io/schemas/adaptive-card.json",
      msteams: { width: "Full" }
    )

    # Upstream serializes the schema field as "schema" (not "$schema").
    assert_equal "http://adaptivecards.io/schemas/adaptive-card.json", card.to_h["schema"]
    assert_equal({ "width" => "Full" }, card.to_h["msteams"])
  end

  def test_message_activity_adds_adaptive_card_attachment
    card = Teams::Cards::AdaptiveCard.new(Teams::Cards::TextBlock.new("Hello"))
    activity = Teams::Api::MessageActivity.new("card").add_card(card)

    attachment = activity.to_h.fetch("attachments").first

    assert_equal "application/vnd.microsoft.card.adaptive", attachment["contentType"]
    assert_equal "AdaptiveCard", attachment.dig("content", "type")
    assert_equal "1.5", attachment.dig("content", "version")
    assert_equal "Hello", attachment.dig("content", "body").first["text"]
  end
end
