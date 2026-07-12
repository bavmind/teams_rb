# Running in Teams

Connect your locally running bot to a real Teams client.

## 1. Register a bot

Create a Teams app with a bot in the [Teams Developer Portal](https://dev.teams.microsoft.com) (or with Microsoft's Teams CLI). You need three values for the app's environment:

- `CLIENT_ID` — the bot's Microsoft App ID
- `CLIENT_SECRET` — a client secret for that app registration
- `TENANT_ID` — your Entra tenant ID (single-tenant bots)

> If you plan to use [user authentication](../in-depth-guides/user-authentication.md), register the bot as an **Azure Bot resource** from the start (Azure portal → Create resource → Azure Bot → "Use existing app registration"). OAuth connection settings only exist there, and converting a Developer Portal registration later means deleting and recreating it.

## 2. Start a tunnel

Teams must reach your machine over HTTPS. With Dev Tunnels:

```sh
devtunnel create teams-bot -a
devtunnel port create teams-bot -p 3978
devtunnel host teams-bot
```

Note the tunnel URL, e.g. `https://abc123-3978.euw.devtunnels.ms`. Dev Tunnels URLs are stable across restarts, so this is one-time setup.

## 3. Point the bot at the tunnel

In the bot registration, set the **messaging endpoint** to `https://<your-tunnel>/api/messages`, and make sure the **Microsoft Teams channel** is enabled.

## 4. Run and install

```sh
bundle exec rackup -p 3978 -o 0.0.0.0
```

Install the app in Teams (Developer Portal → Preview in Teams) and send it a message. Inbound requests are JWT-validated with your real credentials — no `skip_auth` needed behind a tunnel.

## Troubleshooting

- **No response in Teams**: check the messaging endpoint URL, the Teams channel, and that the tunnel and server are both running. The app logs every inbound activity at debug level and every rejected request at warn level.
- **401s in your logs**: the requests are reaching you but failing validation — usually a `CLIENT_ID`/`TENANT_ID` mismatch with the registration.
- **Teams caches aggressively**: after manifest changes, fully quit and reopen the Teams client.
- **At-least-once delivery**: Bot Framework redelivers activities when your bot errors or responds slowly. If a handler's side effects must not repeat, deduplicate by `ctx.activity.id`.
