# Code basics

The quickstart's `config.ru` is a complete Teams app. Here's what each piece does, and the concepts you'll use everywhere else.

## The App

```ruby
teams = Teams::App.new
```

`Teams::App` is the heart of the SDK — it owns the route table, the API client, token management, and inbound request validation. By default it reads `CLIENT_ID`, `CLIENT_SECRET`, and `TENANT_ID` from the environment; every option can also be passed explicitly ([App basics](../essentials/app-basics.md) lists them all).

## Handlers

```ruby
teams.on_message do |ctx|
  ctx.typing
  ctx.reply "echo: #{ctx.activity.text}"
end
```

Handlers register against activity routes: `on_message` for messages (optionally filtered by a pattern), `on_dialog_open` for dialog invokes, `on_message_ext_query` for message extension searches, and so on — [Listening to activities](../essentials/on-activity.md) has the full list. Multiple handlers can match one activity; a handler with a second block parameter controls chaining:

```ruby
teams.use do |ctx, nxt|
  puts "inbound #{ctx.activity.type}"
  nxt.call   # continue to the next matching handler
end
```

## The activity context

Every handler receives a `ctx` with everything about the current activity:

| Member | What it is |
|---|---|
| `ctx.activity` | The inbound activity model — `type`, `text`, `from`, `conversation`, `value`, plus raw payload access via `ctx.activity.raw` |
| `ctx.ref` | The conversation reference — persist `ctx.ref.to_h` to message this conversation later |
| `ctx.post` / `ctx.reply` / `ctx.quote` / `ctx.update` / `ctx.typing` | Sending — see [Sending messages](../essentials/sending-messages.md) |
| `ctx.stream` | Chunked streaming responses — see [Streaming](../in-depth-guides/streaming.md) |
| `ctx.sign_in` / `ctx.sign_out` | User OAuth — see [User authentication](../in-depth-guides/user-authentication.md) |
| `ctx.api` | The low-level [API client](../essentials/api-client.md) |
| `ctx.app_graph` / `ctx.user_graph` | [Microsoft Graph](../essentials/graph.md) clients |
| `ctx.storage`, `ctx.log` | The app's state store and logger |

## The Rack endpoint

```ruby
run teams.to_rack
```

`to_rack` returns a plain Rack app serving the Teams messaging endpoint (default `/api/messages`) — mount it in `config.ru`, or route to it from Rails:

```ruby
# config/routes.rb
post "/api/messages" => TEAMS_BOT.to_rack
```

## One naming note

The Microsoft SDKs call their send operation `send`; Ruby uses `post` because `Object#send` is core Ruby. Treat `post` as Ruby's spelling of SDK `send` — including its update-when-id-present behavior. `reply` keeps full SDK reply semantics (reply threading plus Teams quoted-reply markup).
