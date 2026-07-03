# teams_rb

Ruby SDK for receiving and sending Microsoft Teams bot messages from Rack/Rails apps.

This first MVP targets the production message-bot path:

- Rack endpoint for Teams messages
- Inbound Teams request validation enabled by default
- Message routing with `on_message`
- Replies, updates, and proactive sends through the Teams API
- Faraday HTTP client
- Minitest test suite

Current live status: receiving a Teams message and replying through Bot Framework has been verified with a Dev Tunnel and Microsoft Teams install.

## Local Usage

From another Ruby app:

```ruby
gem "teams_rb", path: "../teams_rb"
```

Then:

```ruby
require "teams"

teams = Teams::App.new

teams.on_message do |ctx|
  ctx.typing
  puts ctx.ref.conversation_id
  ctx.reply "reply: #{ctx.activity.text.inspect}"
  ctx.post "post: #{ctx.activity.text.inspect}"
end

run teams.to_rack
```

Suggested action submit invokes use the SDK route name and expose the submitted payload through `ctx.activity.value`:

```ruby
teams.on_suggested_action_submit do |ctx|
  ctx.post "submitted: #{ctx.activity.value.to_h.inspect}"
end
```

Reactions use the API client shape from the Microsoft SDKs:

```ruby
teams.api.reactions.add(conversation_id, activity_id, "like")
teams.api.reactions.delete(conversation_id, activity_id, "like")
```

To update a message later, keep the activity id returned from the original send:

```ruby
sent = teams.post(conversation_id, "We have 2 Free iPhones, ready to pick up. While supplies last")

teams.update(conversation_id, sent.fetch("id"), "Free phones gone now.")
# equivalent SDK-send style:
teams.post(conversation_id, Teams::Api::MessageActivity.new("Free phones gone now.").with_id(sent.fetch("id")))
# lower-level parity surface:
teams.api.update_activity(conversation_id, sent.fetch("id"), Teams::Api::MessageActivity.new("Free phones gone now."))
```

More Rack examples live in `examples/`.

The Teams messaging endpoint defaults to `/api/messages`, matching the TypeScript and Python SDK defaults. If your app needs another path, configure it on the app and register the same full URL with Teams:

```ruby
teams = Teams::App.new(messaging_endpoint: "/bot/incoming")
run teams.to_rack
```

Use `ctx.post` for a plain message in the conversation. The Microsoft Teams SDKs call this `send`, but Ruby already defines `Object#send` for dynamic dispatch, so this SDK uses `post` for the public Ruby API. Treat `post` as Ruby's spelling of SDK `send`: if the activity already has an `id`, it updates that activity instead of creating a new one. Use `ctx.reply` when you want Teams reply semantics: `replyToId` plus the Teams `quotedReply` entity and quote placeholder, matching the Microsoft SDK behavior. Use `ctx.update(activity_id, activity)` to replace a previous bot message in the current conversation.

`ctx.ref` returns a `Teams::Api::ConversationReference`, matching the Teams SDK concept used for the current conversation. The same object is also available as `ctx.conversation_reference`. Store `ctx.ref.to_h` from a validated inbound activity if you need to post, reply, or update later from a job, then restore it with `Teams::Api::ConversationReference.from_h` and pass its `conversation_id` and `service_url` to `teams.post` / `teams.reply` / `teams.update`.

For modeled Ruby object access, use snake_case field names:

```ruby
ctx.activity.service_url
ctx.activity.reply_to_id
ctx.activity.from.aad_object_id
ctx.activity.conversation.conversation_type
```

Raw payload access stays unchanged through `raw` / `to_h`:

```ruby
ctx.activity.raw["serviceUrl"]
ctx.activity.raw.dig("from", "aadObjectId")
```

Quoted replies use the same SDK concepts as TypeScript, Python, and .NET:

```ruby
ctx.reply "auto-quotes the inbound activity"
ctx.quote "message-id", "quotes a specific activity"

message = Teams::Api::MessageActivity.new
  .add_quote("message-id", "builder response")

quotes = ctx.activity.get_quoted_messages
```

For formatted text, use a message activity with `text_format`:

```ruby
ctx.post Teams::Api::MessageActivity.new("plain text", text_format: "plain")
ctx.post Teams::Api::MessageActivity.new("**markdown**", text_format: "markdown")
ctx.post Teams::Api::MessageActivity.new("line 1<br>line 2", text_format: "xml")
ctx.post Teams::Api::MessageActivity.new("extended markdown", text_format: "extendedmarkdown")
```

For streamed responses, use `ctx.stream`:

```ruby
teams.on_message do |ctx|
  ctx.stream.update("Thinking...")
  ctx.stream.emit("Hello")
  ctx.stream.emit(", world")
end
```

To mark a final message as AI-generated, use `add_ai_generated` on `MessageActivity`. This also works as the final streamed message metadata:

```ruby
teams.on_message do |ctx|
  ctx.stream.update("Thinking...")
  ctx.stream.emit("Hello")
  ctx.stream.emit("! I'm a friendly AI bot. ")
  ctx.stream.emit(Teams::Api::MessageActivity.new.add_ai_generated)
end
```

For citations, include the matching inline position marker in the text and add the citation to the message activity:

```ruby
message = Teams::Api::MessageActivity.new("The policy allows this [1].")
  .add_ai_generated
  .add_citation(
    1,
    Teams::Api::CitationAppearance.new(
      name: "Policy Guide",
      abstract: "Relevant policy excerpt",
      url: "https://example.com/policy",
      icon: "PDF"
    )
  )

ctx.post message
```

Citation `name` and `abstract` are required. Teams expects `name` to be at most 80 characters and `abstract` to be at most 160 characters. Keywords are documented as limited to 3 items, each at most 28 characters.

To show Teams' built-in feedback controls on a message:

```ruby
ctx.post Teams::Api::MessageActivity.new("Was this helpful?").add_feedback
```

For a custom feedback dialog flow, use `custom`:

```ruby
ctx.post Teams::Api::MessageActivity.new("Was this helpful?").add_feedback("custom")
```

For Adaptive Cards, use `Teams::Cards` objects directly or wrap them in a message activity:

```ruby
card = Teams::Cards::AdaptiveCard.new(
  Teams::Cards::TextBlock.new("Create ticket", weight: "Bolder", size: "Large", wrap: true),
  Teams::Cards::TextInput.new(id: "title", label: "Title", is_required: true),
  actions: [
    Teams::Cards::SubmitAction.new(title: "Create", data: { action: "create_ticket" })
  ]
)

ctx.post card
ctx.reply card
ctx.post Teams::Api::MessageActivity.new.add_card(card)
```

For local tests only:

```ruby
teams = Teams::App.new(skip_auth: true)
```

Production apps should provide `CLIENT_ID`, `CLIENT_SECRET`, and `TENANT_ID`.
