# App basics

## Construction

`Teams::App.new` reads configuration from the environment by default; every value can be passed explicitly:

| Env var | Keyword | Required | Purpose |
|---|---|---|---|
| `CLIENT_ID` | `client_id:` | production | Bot's Microsoft App ID — bot tokens and inbound JWT audiences |
| `CLIENT_SECRET` | `client_secret:` | production | Client secret for the client-credentials flow |
| `TENANT_ID` | `tenant_id:` | single-tenant | Entra tenant for bot tokens and tenant-issuer validation |
| `SERVICE_URL` | `service_url:` | no | Default Bot Framework URL for proactive sends (inbound requests always use the activity's own service URL) |
| `DANGEROUSLY_ALLOW_UNAUTHENTICATED_REQUESTS` | `dangerously_allow_unauthenticated_requests:` | no | Disables inbound validation — local development only (`skip_auth:` is a deprecated alias) |
| — | `messaging_endpoint:` | no | Inbound path, default `/api/messages` |
| — | `default_connection_name:` | no | OAuth connection name for user sign-in, default `"graph"` |
| — | `logger:`, `storage:`, `cloud:` | no | Logger (stdout default), state store (in-memory default), cloud environment for sovereign clouds |

Without credentials the app logs a startup warning and rejects every inbound request unless `dangerously_allow_unauthenticated_requests: true` was set explicitly — the same behavior as the TypeScript, Python, and .NET SDKs.

## One app instance

Construct the app once at boot and share it; it is safe under multi-threaded servers (Puma etc.) — the token cache, storage, and JWKS caches are lock-protected, and per-request state lives on the context.

```ruby
# config/initializers/teams_bot.rb (Rails) or config.ru (Rack)
TEAMS_BOT = Teams::App.new

TEAMS_BOT.on_message do |ctx|
  ctx.reply "hello"
end
```

## Serving

`to_rack` produces the Rack app:

```ruby
# Rack
run TEAMS_BOT.to_rack

# Rails — route the endpoint path; this preserves the request path,
# which the endpoint check relies on
post "/api/messages" => TEAMS_BOT.to_rack
```

Handlers run inside the web request. Keep them fast; move slow work (LLM calls, long queries) to a job and deliver results later via [proactive messaging](proactive-messaging.md).

## Storage

`ctx.storage` (and `app.storage`) is a simple key-value store with `get`/`set`/`delete`. The default `Teams::Storage::MemoryStore` is thread-safe but process-local — substitute anything answering the same three methods (backed by Redis, Active Record, …) via `storage:`.
