# Streaming

Stream a response in chunks — the "typing then progressively filling in" experience used for AI answers. `ctx.stream` handles the Teams streaming protocol; you just emit.

## Emitting

```ruby
teams.on_message do |ctx|
  ctx.stream.update "Thinking..."     # informative status line (visible above the response)
  answer_tokens.each { |t| ctx.stream.emit(t) }
  # the stream finalizes automatically when the handler returns
end
```

- `emit(text)` appends to the streamed message.
- `update(text)` sends an informative status update (shown before content starts).
- `clear_text` discards accumulated text — e.g. to replace streamed text with a final card.
- `close` finalizes explicitly; it's called for you when the handler returns.

Emits are queued and flushed by a background thread, matching the TypeScript and Python streamers: rapid emits coalesce into fewer chunks (spaced to respect Teams rate limits), and `close` waits for the queue to drain before sending the final message.

## Final message metadata

The final streamed message can carry the same enrichment as a normal message:

```ruby
ctx.stream.emit "Here's the summary. "
ctx.stream.emit Teams::Api::MessageActivity.new.add_ai_generated
```

## Events

```ruby
ctx.stream.on_chunk { |sent| ctx.log.debug("chunk #{sent.id}") }
ctx.stream.on_close { |sent| Analytics.record_stream(sent.id) }
```

`on_chunk` fires with the `SentActivity` of each shipped chunk; `on_close` fires once with the final `SentActivity`. Handlers persist across stream reuse.

## Reuse and typed errors

Emitting again after `close` starts a **new** streamed message on the same stream. If Teams stops a stream, the SDK raises typed errors:

- `Teams::StreamCancelledError` — the user cancelled (sticky: the next `emit` also raises)
- `Teams::StreamNotAllowedError`, `Teams::TerminalStreamError` — terminal failures

Chunk-send errors are recorded on the stream and surface when `close` sends the final message. A stream that exceeds the Teams two-minute limit finalizes automatically by updating the streamed message in place.

## Gotchas

- The Teams client renders **only one** streamed message per inbound turn well; use reuse deliberately.
- A **card-only** stream (no text ever emitted) sends nothing, matching the other SDKs — emit text chunks first, then `clear_text` and emit the card as the final message.
