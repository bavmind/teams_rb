# Adaptive Cards

`Teams::Cards` provides typed builders for all 112 Adaptive Card element classes. They're generated from the Microsoft SDK's own card model, so they serialize to exactly the same JSON — including the host-specific defaults the Teams client expects.

## Building a card

```ruby
C = Teams::Cards

card = C::AdaptiveCard.new(
  C::TextBlock.new("Weekly report", size: "Large", weight: "Bolder"),
  C::TextBlock.new("Everything is on track.", wrap: true),
  C::FactSet.new(facts: [
    C::Fact.new(title: "Status", value: "Green"),
    C::Fact.new(title: "Owner", value: "Devran")
  ]),
  actions: [
    C::OpenUrlAction.new("https://example.com", title: "Details"),
    C::SubmitAction.new(title: "Acknowledge", data: { "action" => "ack" })
  ]
)

ctx.post Teams::Api::MessageActivity.new.add_card(card)
```

Constructors take positional children where it reads naturally (a `TextBlock`'s text, a card's body elements) and keyword arguments for properties. Ruby conveniences like `add_item` / `add_action` / `add_choice` are available alongside the constructor forms.

## Sending cards

```ruby
ctx.post card          # card as the sole attachment
ctx.reply card
ctx.post Teams::Api::MessageActivity.new("See attached").add_card(card)
```

A raw Hash works too, as an escape hatch — `add_card({ "type" => "AdaptiveCard", ... })`.

## Actions and submissions

`SubmitAction` data comes back as a message activity with no text and the data in `ctx.activity.value` — **answer it with `post`, never `reply`** (quoting the invisible submit activity is rejected by Teams):

```ruby
teams.on_message do |ctx, nxt|
  next nxt.call unless ctx.activity.text.nil? && ctx.activity.raw["value"]
  ctx.post "Got: #{ctx.activity.raw["value"].inspect}"
end
```

For richer action flows — opening a modal form from a card button — see [Dialogs](dialogs.md).

## Dynamic typeahead search

An `Input.ChoiceSet` with `choices.data` (`Data.Query`) fetches its choices from your bot as the user types. Teams sends an `application/search` invoke; answer it with `on_card_search`:

```ruby
teams.on_card_search do |ctx|
  query = ctx.activity.value.query_text
  Teams::Api::SearchResponse.new(
    CITIES.grep(/#{Regexp.escape(query)}/i).map do |city|
      Teams::Api::SearchInvokeResult.new(title: city, value: city)
    end
  )
end
```

`ctx.activity.value` also carries `dataset` (the `Data.Query` dataset id, for cards with several dynamic inputs) and `query_options` with `skip`/`top` for paging large result sets.

## Regenerating

The card classes are generated; don't hand-edit `lib/teams/cards/generated.rb`. To regenerate after an upstream card-model change:

```sh
bundle exec rake cards:generate   # reads a sibling teams.py checkout; TEAMS_PY_PATH overrides
bundle exec rake test             # golden tests assert byte-identical serialization
```

## A note on validation

Cards serialize faithfully but the SDK does not validate field values — invalid values pass straight through, exactly as raw hashes would. One live gotcha worth knowing: `CodeBlock`'s `language` is a server-side enum; unlisted values (including "Ruby") are rejected — use `"PlainText"`.
