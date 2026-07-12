# Microsoft Graph

A thin Graph request client, following the TypeScript SDK's core Graph client. The raw request surface is the API (like TypeScript's `client.http` escape hatch); there are no generated endpoint wrappers, and Ruby has no official Graph SDK to delegate to.

## Two identities

```ruby
teams.graph          # the app's own identity (app-only tokens) — also ctx.app_graph
ctx.user_graph       # the signed-in user's identity
```

- **App identity** uses the client-credentials flow with the Graph scope. Grant the app **application permissions** in Entra for whatever it reads/writes.
- **User identity** uses the token from [user sign-in](../in-depth-guides/user-authentication.md) and raises `Teams::Error` when the user hasn't signed in. The token carries the OAuth connection's **delegated** scopes.

## Requests

`get` / `post` / `patch` / `put` / `delete`, paths relative to `/v1.0`, parsed-hash returns:

```ruby
me = ctx.user_graph.get("/me")
ctx.reply "You are #{me["displayName"]} (#{me["userPrincipalName"]})"

teams.graph.get("/users", params: { "$top" => 5, "$select" => "displayName" })
teams.graph.post("/users/#{user_id}/sendMail", json: { message: { subject: "Hi" } })
```

## Errors

Failures raise `Teams::GraphError` with `status`, the Graph error `code` (e.g. `Authorization_RequestDenied`), and the full response `body`:

```ruby
begin
  teams.graph.get("/users")
rescue Teams::GraphError => e
  ctx.log.warn("Graph denied: #{e.code}") if e.status == 403
end
```

## Sovereign clouds

The Graph host derives from the configured cloud's graph scope automatically; `Teams::Graph::Client.new(token:, base_url_root: "https://graph.microsoft.us")` overrides it for hand-built clients.
