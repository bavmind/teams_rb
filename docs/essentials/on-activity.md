# Listening to activities

Handlers register against named routes, matching the Python SDK's handler names.

## Messages

```ruby
teams.on_message do |ctx|                 # every message
  ctx.reply "you said: #{ctx.activity.text}"
end

teams.on_message(/^help$/i) do |ctx|      # pattern-filtered (Regexp or exact String)
  ctx.reply "try: search, create, login"
end
```

Message edits and restores route separately:

```ruby
teams.on_message_update { |ctx| }          # any messageUpdate activity
teams.on_edit_message { |ctx| }            # user edited a message
teams.on_undelete_message { |ctx| }        # user restored a deleted message
```

## Invokes

Each invoke family has named routes — their handler return values become the invoke's HTTP response body:

- Dialogs: `on_dialog_open(dialog_id = nil)`, `on_dialog_submit(action = nil)` — [guide](../in-depth-guides/dialogs.md)
- Message extensions: `on_message_ext_query`, `on_message_ext_submit`, `on_message_ext_open`, `on_message_ext_query_link`, and five more — [guide](../in-depth-guides/message-extensions.md)
- Sign-in: `on_signin_token_exchange`, `on_signin_verify_state`, `on_signin_failure` (defaults provided — [guide](../in-depth-guides/user-authentication.md))
- Feedback: `on_message_submit_feedback` (thumbs up/down from `add_feedback` — [guide](../in-depth-guides/feedback.md)), `on_message_submit` for any `message/submitAction`
- `on_suggested_action_submit` for suggested-action submissions

## Meeting events

```ruby
teams.on_meeting_start { |ctx| ctx.post "Meeting #{ctx.activity.value.title} started" }
teams.on_meeting_end   { |ctx| }
```

See [Meeting events](../in-depth-guides/meeting-events.md) for the payload details.

## Middleware

`use` registers a handler that sees every activity; calling the second parameter continues the chain. Any handler that declares two parameters participates in chaining:

```ruby
teams.use do |ctx, nxt|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  nxt.call
ensure
  ctx.log.info("#{ctx.activity.type} handled in #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)}s")
end
```

Handlers run in registration order among those whose route matches the activity; without `nxt.call`, the chain stops.

## The escape hatch

`teams.on(type)` matches raw activity types (`"message"`, `"invoke"`, `"messageReaction"`, `"conversationUpdate"`, …) for anything without a named route. Prefer the named routes when one exists.

```ruby
teams.on("messageReaction") do |ctx|
  reaction = ctx.activity.raw["reactionsAdded"]&.first
  ctx.post "thanks for the #{reaction["type"]}!" if reaction
end
```

## Error semantics

A handler that raises produces a 500 response, and Bot Framework then **redelivers the activity** (same `ctx.activity.id`) — this is SDK-family behavior. Deduplicate side effects by activity id when that matters.
