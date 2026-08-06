# Running in Teams

Connect your locally running bot to a real Teams client with the [Teams CLI](https://www.npmjs.com/package/@microsoft/teams.cli).

## 1. Install and sign in

The CLI requires Node.js 20 or newer:

```sh
npm install -g @microsoft/teams.cli
teams login
teams status
```

`teams status` should report that sideloading is enabled. If it is disabled, your tenant administrator must enable custom app upload before you can install the bot.

## 2. Start a tunnel

Teams must reach your machine over HTTPS. With Dev Tunnels:

```sh
devtunnel create teams-bot -a
devtunnel port create teams-bot -p 3978
devtunnel host teams-bot
```

Note the tunnel URL, such as `https://abc123-3978.euw.devtunnels.ms`. Dev Tunnels URLs are stable across restarts, so creation is a one-time step.

## 3. Register the app and bot

From your project directory, pass the public endpoint to the CLI:

```sh
teams app create \
  --name my-teams-ruby-bot \
  --endpoint https://<your-tunnel>/api/messages
```

The CLI creates the app registration, manifest, bot, and Teams app. It prints the Teams App ID, an **Install in Teams** link, and the three values your Ruby app needs:

- `CLIENT_ID` — the bot's Microsoft App ID
- `CLIENT_SECRET` — the bot's client secret
- `TENANT_ID` — the Entra tenant ID

> If you plan to use [user authentication](../in-depth-guides/user-authentication.md), create an Azure-hosted bot with the CLI's `--azure`, `--subscription`, and `--resource-group` options. OAuth connection settings are not available for Teams-managed bots.

You can instead configure the same resources manually in the [Teams Developer Portal](https://dev.teams.microsoft.com/apps).

## 4. Run and install

Start the bot with the credentials printed by the CLI:

```sh
CLIENT_ID=... CLIENT_SECRET=... TENANT_ID=... bundle exec puma -p 3978
```

Open the **Install in Teams** link and send the bot a message. If you need the link again, run `teams app get <teams-app-id> --install-link`.

Inbound requests are JWT-validated with your real credentials; no `dangerously_allow_unauthenticated_requests` is needed behind the tunnel.

## Troubleshooting

- **No response in Teams**: run `teams app doctor <teams-app-id>`, then check that the tunnel and server are running.
- **401s in your logs**: the requests are reaching you but failing validation, usually because the running app has credentials from a different registration.
- **Sideloading disabled**: ask your tenant administrator to enable custom app upload.
- **Teams caches aggressively**: after manifest changes, fully quit and reopen the Teams client.
- **At-least-once delivery**: Bot Framework redelivers activities when your bot errors or responds slowly. If a handler's side effects must not repeat, deduplicate by `ctx.activity.id`.
