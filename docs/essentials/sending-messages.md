# Sending messages

## The four verbs

```ruby
ctx.post "a plain message in the conversation"
ctx.reply "a threaded reply, quoting the inbound message"
ctx.quote "message-id", "a reply quoting a specific message"
ctx.update "activity-id", "replaces a previous bot message"
```

`post` is Ruby's spelling of the SDKs' `send` (Ruby reserves `Object#send`), with identical semantics — including: an activity that already carries an `id` is **updated** instead of created. `ctx.update` is sugar over exactly that. `reply` adds the Teams quoted-reply entity and placeholder, matching the other SDKs.

All sends accept a String, a `Teams::Api::MessageActivity`, an Adaptive Card, or a raw activity Hash (symbol or string keys — they're normalized).

## SentActivity

Every send returns a `Teams::Api::SentActivity` — the outbound activity merged with the server's response. Keep its `id` to edit later:

```ruby
sent = ctx.post "Working on it..."
# ...later...
ctx.update sent.id, "Done!"
```

> **Updates replace the activity entirely.** Metadata like the AI-generated label, sensitivity labels, citations, and mentions must be re-attached on every update or they disappear.

## Message activities

`Teams::Api::MessageActivity` is the builder for anything beyond plain text:

```ruby
ctx.post Teams::Api::MessageActivity.new("**markdown**", text_format: "markdown")
# text_format: plain | markdown | xml | extendedmarkdown
# ("extendedmarkdown" is in public preview and may be subject to change)

ctx.post Teams::Api::MessageActivity.new("Quarterly numbers")
  .add_ai_generated                                          # "AI generated" badge
  .add_sensitivity_label("Confidential", description: "Internal only")
  .add_feedback                                              # thumbs up/down feedback buttons
```

Mentions:

```ruby
ctx.post Teams::Api::MessageActivity.new("ping ").add_mention(ctx.activity.from.to_h)

if ctx.activity.recipient_mentioned?
  ctx.reply "you said: #{ctx.activity.strip_mentions_text}"
end
```

Citations (for AI answers) attach numbered references — `[1]` in the text links to the citation:

```ruby
message = Teams::Api::MessageActivity.new("Revenue grew 40% [1].").add_ai_generated
message.add_citation(1, { "name" => "Q3 Report", "url" => "https://example.com/q3" })
ctx.post message
```

> A citation's inline `text` content must be a **stringified Adaptive Card** — Teams rejects the whole message with a 400 otherwise.

## Typing

```ruby
ctx.typing               # animated ellipsis in the chat
```

`ctx.typing(text)` exists for wire parity, but the Teams client doesn't render text on a plain typing activity — for a visible status line use `ctx.stream.update("Thinking...")` ([Streaming](../in-depth-guides/streaming.md)).

## Targeted messages

When the inbound message targets the bot (`recipient.isTargeted`), `ctx.post` and `ctx.reply` automatically answer as targeted messages visible only to that user, matching TypeScript/Python — including the `targetedMessageInfo` entity and the targeted API routes. Targeted messages aren't supported in 1:1 chats (the SDK raises).

## Delivery semantics

Bot Framework delivers **at least once**: a slow or failing bot sees the same activity again with the same `ctx.activity.id`. The SDK doesn't deduplicate (none of the SDKs do) — if a side effect must not repeat, guard it by activity id.
