# frozen_string_literal: true

require_relative "test_helper"

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

    assert_equal(
      {
        "type" => "AdaptiveCard",
        "version" => "1.5",
        "body" => [
          { "type" => "TextBlock", "weight" => "Bolder", "size" => "Large", "wrap" => true, "text" => "Create ticket" },
          {
            "type" => "Input.Text",
            "label" => "Title",
            "placeholder" => "Short summary",
            "isRequired" => true,
            "errorMessage" => "Title is required",
            "id" => "title"
          },
          {
            "type" => "Input.ChoiceSet",
            "label" => "Kind",
            "style" => "expanded",
            "id" => "kind",
            "choices" => [
              { "title" => "Bug", "value" => "bug" },
              { "title" => "Question", "value" => "question" }
            ]
          }
        ],
        "actions" => [
          { "type" => "Action.Submit", "title" => "Create", "data" => { "action" => "create_ticket" } },
          { "type" => "Action.OpenUrl", "title" => "Help", "url" => "https://example.com/help" }
        ]
      },
      card.to_h
    )
  end

  def test_card_builder_methods
    card = Teams::Cards::AdaptiveCard.new
      .add_item(Teams::Cards::TextBlock.new("Status").with_text("Updated status"))
      .add_action(Teams::Cards::ExecuteAction.new(title: "Refresh").with_verb("refresh"))
      .with_options(fallback_text: "Fallback")

    assert_equal "Updated status", card.to_h.fetch("body").first.fetch("text")
    assert_equal "Fallback", card.to_h.fetch("fallbackText")
    assert_equal(
      { "type" => "Action.Execute", "title" => "Refresh", "verb" => "refresh" },
      card.to_h.fetch("actions").first
    )
  end

  def test_special_json_keys
    card = Teams::Cards::AdaptiveCard.new(
      schema: "http://adaptivecards.io/schemas/adaptive-card.json",
      fallback_text: "Could not render card",
      msteams: { width: "Full" }
    )

    assert_equal "http://adaptivecards.io/schemas/adaptive-card.json", card.to_h["$schema"]
    assert_equal "Could not render card", card.to_h["fallbackText"]
    assert_equal({ "width" => "Full" }, card.to_h["msteams"])
  end

  def test_message_activity_adds_adaptive_card_attachment
    card = Teams::Cards::AdaptiveCard.new(Teams::Cards::TextBlock.new("Hello"))
    activity = Teams::Api::MessageActivity.new("card").add_card(card)

    assert_equal(
      {
        "contentType" => "application/vnd.microsoft.card.adaptive",
        "content" => {
          "type" => "AdaptiveCard",
          "version" => "1.5",
          "body" => [{ "type" => "TextBlock", "text" => "Hello" }]
        }
      },
      activity.to_h.fetch("attachments").first
    )
  end
end
