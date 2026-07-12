# Observability

## Logging

The app logs to the `logger:` you pass (stdout by default). At debug level it logs every inbound activity (type, invoke name, id, matched route count) and every API request; at warn level it logs rejected requests (invalid JSON, auth failures) and OAuth/streaming issues; handler errors log at error level before the 500 response.

```ruby
teams = Teams::App.new(logger: Rails.logger)
```

Inside handlers, `ctx.log` is that same logger.

## Middleware

`use` wraps every activity — the place for timing, request ids, structured context, or short-circuiting. The second block parameter continues the chain:

```ruby
teams.use do |ctx, nxt|
  ctx.log.info("→ #{ctx.activity.type} from #{ctx.activity.from&.id}")
  nxt.call
end
```

Middleware runs before route handlers; omit `nxt.call` to stop processing (e.g. to drop an activity). See [Listening to activities](../essentials/on-activity.md#middleware) for the ordering rules.

## Health

The messaging endpoint returns `401` to unauthenticated requests once credentials are configured — a simple external signal that the app is up and validating. A `POST /api/messages` with an empty body is the cheapest probe.
