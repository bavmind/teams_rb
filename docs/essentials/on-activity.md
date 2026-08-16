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

## Conversation updates

`on_conversation_update` matches any `conversationUpdate` activity (members added/removed, channel and team changes). The channel/team lifecycle sub-events also have named routes, matched on `channelData.eventType`:

```ruby
teams.on_conversation_update { |ctx| }     # any conversationUpdate activity
teams.on_channel_created  { |ctx| ctx.post "Welcome to #{ctx.activity.channel_data.channel.name}!" }
teams.on_channel_deleted  { |ctx| }        # also: on_channel_renamed, on_channel_restored
teams.on_team_renamed     { |ctx| }        # also: on_team_archived, on_team_unarchived,
                                           #   on_team_deleted, on_team_hard_deleted, on_team_restored
```

A generic `on_conversation_update` registered before a specific route sees the activity first; declare `|ctx, nxt|` and call `nxt.call` to continue to the specific route (see Middleware below).

## Agent 365 lifecycle events

`on_agent_lifecycle` matches any `agentLifecycle` event (sent when this app runs as an Agent 365 agentic user); the variants also have named routes, matched on the activity's `valueType`:

```ruby
teams.on_agent_lifecycle { |ctx| }                # any agentLifecycle event
teams.on_agentic_user_identity_created { |ctx| }  # also: identity_updated, manager_updated,
teams.on_agentic_user_enabled { |ctx| }           #   disabled, deleted, undeleted,
                                                  #   workload_onboarding_updated
```

The event value exposes `tenant_id`, `agentic_user_id`, `agentic_app_instance_id`, `agent_identity_blueprint_id`, `version`, and per-variant fields (`manager`, `deletion_reason`, `workload_name`, …).

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
