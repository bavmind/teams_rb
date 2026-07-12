# Tabs and remote functions

A tab is a web page hosted inside Teams. Serve the page from your own app (Rails route, `public/`, any host) — the SDK doesn't host pages, since your framework already does that better. What the SDK provides is **remote functions**: authenticated endpoints your tab's JavaScript calls to reach the bot backend as the signed-in user.

## Registering a function

```ruby
teams.on_function("create-ticket") do |ctx|
  ticket = Ticket.create!(title: ctx.data["title"], creator_oid: ctx.user_id)
  ctx.post "#{ctx.user_name} created ticket ##{ticket.id} from the tab"
  { "id" => ticket.id }
end
```

This serves `POST /api/functions/create-ticket`. The handler receives a `FunctionContext`:

- `ctx.data` — the parsed JSON request body
- `ctx.user_id`, `ctx.tenant_id`, `ctx.user_name` — from the validated Entra token
- `ctx.chat_id`, `ctx.channel_id`, `ctx.meeting_id`, `ctx.team_id`, `ctx.page_id`, `ctx.app_session_id` — from the `X-Teams-*` client-context headers
- `ctx.conversation_id` — resolves the conversation (validating membership; creating the 1:1 in personal scope)
- `ctx.post` — sends into the resolved conversation proactively

The handler's return value becomes the JSON response body.

## Validation

Every call is validated like the TypeScript/Python SDKs: required `X-Teams-App-Session-Id` / `X-Teams-Page-Id` / bearer headers, the Entra token verified against your app registration (client id audience forms, tenant issuer), and the `oid`/`tid`/`name` claims. Invalid requests get a `401` with a `detail` message; unregistered names get a `404`.

## Calling from the tab

The tab page acquires a token through the Teams JS SDK and posts it with the client-context headers:

```js
const token = await microsoftTeams.authentication.getAuthToken();
const context = await microsoftTeams.app.getContext();

await fetch("/api/functions/create-ticket", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Authorization": "Bearer " + token,
    "X-Teams-App-Session-Id": context.app.sessionId,
    "X-Teams-Page-Id": context.page.id,
    ...(context.chat?.id ? { "X-Teams-Chat-Id": context.chat.id } : {})
  },
  body: JSON.stringify({ title: "New ticket" })
});
```

## SSO setup

Tab SSO needs an **Application ID URI whose domain matches the tab's origin**, with `requestedAccessTokenVersion: 2` on the app registration:

- Application ID URI: `api://<your-tab-domain>/<app-id>` (a distinct path suffix like `/<app-id>/tab` avoids collisions if the base URI is taken)
- Pre-authorize the two Teams client app ids (`1fec8e78-bce4-4aaf-ab1b-5451cc387264`, `5e3ce6c0-2b1f-4285-8d4b-75ee78787346`) on the exposed `access_as_user` scope
- Manifest `webApplicationInfo.resource` must match the Application ID URI exactly
- Manifest `staticTabs` entry points `contentUrl` at your page

> Watch for **duplicate app registrations** — the Developer Portal can create a second one; make sure the SSO configuration lands on the registration whose client id your bot uses.
