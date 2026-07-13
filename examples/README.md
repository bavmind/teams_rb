# teams_rb examples

Each example is a Rack app. Use any Rack server; for example, with Puma:

```sh
bundle exec puma examples/basic_echo.ru -p 3978
```

Use the public tunnel URL as the Teams bot messaging endpoint:

```text
https://your-tunnel-url/api/messages
```

## Files

- `config.ru`: default quick echo app.
- `basic_echo.ru`: typing, reply, and post.
- `formatted_messages.ru`: plain, markdown, xml, and extendedmarkdown text formats.
- `adaptive_card.ru`: basic `Teams::Cards` Adaptive Card send/reply.
- `raw_adaptive_card.ru`: raw Adaptive Card JSON-style hash with sample data rendered in Ruby.
- `conversation_reference.ru`: store and restore `ctx.ref` for later proactive posts.
- `activity_debug.ru`: formatted activity/client debug output.

Production apps should provide `CLIENT_ID`, `CLIENT_SECRET`, and `TENANT_ID`.
