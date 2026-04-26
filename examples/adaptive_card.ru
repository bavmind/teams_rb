# frozen_string_literal: true

require "bundler/setup"
require "teams"

teams = Teams::App.new

teams.on_message do |ctx|
  ctx.typing

  card = Teams::Cards::AdaptiveCard.new(
    Teams::Cards::TextBlock.new("Create ticket", weight: "Bolder", size: "Large", wrap: true),
    Teams::Cards::TextBlock.new("This card was built with teams_rb card objects.", wrap: true),
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
      Teams::Cards::OpenUrlAction.new("https://adaptivecards.io", title: "Adaptive Cards")
    ]
  )

  ctx.reply card
  ctx.post Teams::Api::MessageActivity.new("Same card as an explicit message attachment").add_card(card)
end

run teams.to_rack
