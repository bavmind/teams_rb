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

teams.on_sign_in do |ctx, token_response|
  ctx.post "Welcome! You're signed in."
end
```

`ctx.sign_in` returns the token when the user is already signed in; otherwise it sends an OAuth card (to a 1:1 conversation when invoked from a group chat) and returns `nil`. The SDK's **default handlers** then complete the sign-in invokes automatically — both the interactive card path (`signin/verifyState`) and silent SSO (`signin/tokenExchange`) — and fire `on_sign_in`. You don't handle the invokes yourself.

`ctx.sign_out` clears the stored token.

## Using the token

Most often through the [user Graph client](../essentials/graph.md):

```ruby
teams.on_sign_in do |ctx, _token|
  me = ctx.user_graph.get("/me")
  ctx.post "Hello #{me["displayName"]}"
end
```

Or the raw token from the token service:

```ruby
response = ctx.api.users.get_token(
  user_id: ctx.activity.from.id, connection_name: "graph", channel_id: ctx.activity.channel_id
)
response.token   # the delegated access token
```

## Custom invoke handling

The defaults run first; handlers you register on `on_signin_verify_state` / `on_signin_token_exchange` / `on_signin_failure` run **after** them, for custom behavior. Don't fetch the token yourself in a verify-state handler — the magic code is single-use and the default already consumed it.
