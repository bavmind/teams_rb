# Message reactions

## Reacting to messages

The bot can add and remove reactions on any message via the API client:

```ruby
teams.on_message do |ctx|
  ctx.api.conversations.add_reaction(ctx.ref.conversation_id, ctx.activity.id, "like")
end

api.conversations.delete_reaction(conversation_id, activity_id, "like")
```

Reaction types: `like`, `heart`, `laugh`, `surprised`, `sad`, `angry`.

## Receiving reactions

When a user reacts to one of the bot's messages, Teams sends a `messageReaction` activity. Route it with the activity-type escape hatch:

```ruby
teams.on("messageReaction") do |ctx|
  added = Array(ctx.activity.raw["reactionsAdded"]).map { |r| r["type"] }
  removed = Array(ctx.activity.raw["reactionsRemoved"]).map { |r| r["type"] }
  ctx.log.info("reactions +#{added.inspect} -#{removed.inspect} on #{ctx.activity.raw["replyToId"]}")
end
```

The reacted-to message's id arrives as `replyToId`. Reaction activities carry no `text` and need no response — return nothing.
