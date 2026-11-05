# User authentication

Sign a user in and act as them — call Microsoft Graph, your own API, anything needing their delegated token. Built on an OAuth connection configured on the bot's Azure registration.

## Azure setup

User auth needs an **OAuth connection setting**, which lives only on an **Azure Bot resource** — a Developer Portal bot registration has no place for it. If your bot was created in the Developer Portal, migrate it: delete the Developer Portal bot registration, create an Azure Bot resource with **"Use existing app registration"** and the same app id, then re-set the messaging endpoint and re-enable the Teams channel. The app id never changes, so Teams sees no difference.

Then on the Azure Bot's Configuration blade → **Add OAuth Connection Settings**:

- **Name** — match `default_connection_name` (default `"graph"`)
- **Service Provider** — Azure Active Directory v2
- **Client id / secret** — reuse the bot's own credentials
- **Tenant ID** — your tenant
- **Scopes** — e.g. `openid profile User.Read`

And in the Entra app registration: add the Web redirect URI `https://token.botframework.com/.auth/web/redirect`, plus the delegated permissions your scopes name. Use **Test Connection** on the saved setting to confirm before touching code.

## The flow

```ruby
teams = Teams::App.new(default_connection_name: "graph")

teams.on_message(/^login$/i) do |ctx|
  token = ctx.sign_in
  ctx.reply "Already signed in!" if token   # nil means a card was sent
end

teams.on_oauth_sign_in do |ctx, token_response|
  ctx.post "Welcome! You're signed in."
end
```

`ctx.sign_in` returns the token when the user is already signed in; otherwise it sends an OAuth card and returns `nil`. In group chats and channels the card is delivered in the conversation as a targeted message only the requesting user sees; in channels the card always uses the sign-in button (silent SSO is not supported in channel scope). The SDK's **default handlers** then complete the sign-in invokes automatically — both the interactive card path (`signin/verifyState`) and silent SSO (`signin/tokenExchange`) — and fire `on_oauth_sign_in`. You don't handle the invokes yourself.

`ctx.sign_out` clears the stored token.

## Using the token

Most often through the [user Graph client](../essentials/graph.md):

```ruby
teams.on_oauth_sign_in do |ctx, _token|
  me = ctx.user_graph.get("/me")
  ctx.post "Hello #{me["displayName"]}"
end
```

Or the raw token: `ctx.get_user_token(connection_name: "graph")` returns it, or `nil` when the user is not signed in. Only the token service's 404 means "not signed in" — any other failure raises, so an outage is never mistaken for a signed-out user (the same applies to `ctx.sign_in`). `ctx.get_connection_status` returns the token status of every OAuth connection on the bot in one call.

## Multiple connections

Register each OAuth connection as a named flow, then sign in, read tokens, and react to completions per connection:

```ruby
github = teams.add_oauth_flow("github", oauth_card_text: "Sign in with GitHub")
graph = teams.add_oauth_flow("graph")

teams.on_message("/github") { |ctx| github.sign_in(ctx) }
teams.on_message("/logout") { |ctx| github.sign_out(ctx) }

github.on_sign_in do |event|
  event.context.post "Signed in to GitHub (#{event.connection_name})"
end
github.on_sign_in_failure do |event|
  event.context.log.warn("GitHub sign-in failed: #{event.code} #{event.message}")
end

teams.get_oauth_flow("GITHUB")   # case-insensitive lookup; raises when not registered
github.get_token(ctx)            # token or nil
github.signed_in?(ctx)
```

`flow.sign_in` always uses the flow's own connection; its card text defaults to the flow's and can be overridden per call. Flow handlers run in registration order and are isolated: one that raises is logged and the rest still run. The app-level `on_oauth_sign_in` still fires for every connection, and `teams.on_oauth_sign_in_failure { |event| ... }` receives each `signin/failure` callback once as a `Teams::OAuth::SignInFailureEvent` (`context`, `connection_name`, `code`, `message`).

### How callbacks find their flow

- **Silent SSO** (`signin/tokenExchange`) names its connection, so it always reaches the right flow.
- **The card's sign-in button** (`signin/verifyState`) carries only a one-time code. The SDK tries the connections in order — the ones with a pending sign-in for this user (newest first), the remaining registered flows, then `default_connection_name` — until one accepts the code; none accepting answers 404.
- **`signin/failure`** carries no connection either. It is attributed to the newest pending sign-in that offered silent SSO; if none can be found, `on_oauth_sign_in_failure` reports `connection_name` `nil` and every registered flow's failure handlers are notified, each with its own connection name.

`flow.sign_in` / `ctx.sign_in` record the pending sign-in in [per-turn state](state.md), which registering a flow turns on when you didn't set `state:`. With `state: false`, pending sign-ins live in a short-lived in-process cache, so a callback handled by another instance cannot be attributed — use shared state storage when running several instances.

Teams delivers one silent-SSO exchange to every client the user is signed in on; the SDK runs it once. Duplicates answer 200 without firing the sign-in events again, both on the same instance and — through conversation state — across instances.

## Custom invoke handling

The defaults run first; handlers you register on `on_signin_verify_state` / `on_signin_token_exchange` / `on_signin_failure` run **after** them, for custom behavior. Don't fetch the token yourself in a verify-state handler — the magic code is single-use and the default already consumed it.
