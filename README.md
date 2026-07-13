# teams_rb — Teams SDK for Ruby

[![Gem Version](https://img.shields.io/gem/v/teams_rb)](https://rubygems.org/gems/teams_rb)
[![Documentation](https://img.shields.io/badge/docs-getting_started-blue)](docs/getting-started/README.md)

A Ruby-native port of the Microsoft Teams SDKs for building Teams bots and apps with Rack or Rails. It includes message routing, proactive messaging, the Bot Framework API client, typed Adaptive Cards, dialogs, message extensions, streaming, meetings, OAuth, Microsoft Graph, tabs, and remote functions.

`teams_rb` preserves the concepts and wire behavior of the official [TypeScript](https://microsoft.github.io/teams-sdk/typescript/getting-started), [Python](https://microsoft.github.io/teams-sdk/python/getting-started), and [C#](https://microsoft.github.io/teams-sdk/csharp/getting-started) SDKs while providing an idiomatic Ruby API. Inbound JWT validation and outbound bot token management are built in.

> **Unofficial.** `teams_rb` is an independent, community-maintained project. It is not affiliated with, endorsed by, or sponsored by Microsoft. The official Teams SDKs are developed by Microsoft at [github.com/microsoft/teams-sdk](https://github.com/microsoft/teams-sdk).

## Getting started

### Prerequisites

- Ruby 4.0 or newer
- A Microsoft 365 tenant with custom app upload enabled
- A public HTTPS tunnel for local development, such as [Dev Tunnels](https://learn.microsoft.com/azure/developer/dev-tunnels/get-started)

### Install

Add the SDK and a Rack server for this standalone example to your `Gemfile`:

```ruby
gem "teams_rb"
gem "puma"
```

Then install it:

```sh
bundle install
```

### Create your first bot

Create a `config.ru`:

```ruby
require "teams"

teams = Teams::App.new

teams.on_message do |ctx|
  ctx.typing
  ctx.reply "echo: #{ctx.activity.text}"
end

run teams.to_rack
```

### Register it with Teams

The easiest registration path is the optional [Teams CLI](https://www.npmjs.com/package/@microsoft/teams.cli), which requires Node.js 20 or newer. Install it, sign in, and check that your tenant allows sideloading:

```sh
npm install -g @microsoft/teams.cli
teams login
teams status
```

Start your HTTPS tunnel, then let the CLI create the app, bot registration, and install link:

```sh
teams app create \
  --name my-teams-ruby-bot \
  --endpoint https://<your-tunnel>/api/messages
```

The command prints `CLIENT_ID`, `CLIENT_SECRET`, `TENANT_ID`, and an **Install in Teams** link. You can also create the app manually in the [Teams Developer Portal](https://dev.teams.microsoft.com/apps).

### Run it

This standalone example uses Puma; `teams_rb` itself does not require a server gem. Start the bot with the credentials printed by the CLI:

```sh
CLIENT_ID=... CLIENT_SECRET=... TENANT_ID=... bundle exec puma -p 3978
```

Open the install link and send the bot a message. It receives Teams activities at `POST /api/messages`, validates each request, and replies to incoming messages.

See [Running in Teams](docs/getting-started/running-in-teams.md) for the complete registration, tunnel, and installation walkthrough.

## Code basics

Handlers can match message text and respond with typed Adaptive Cards:

```ruby
teams.on_message(/^status$/i) do |ctx|
  ctx.typing

  card = Teams::Cards::AdaptiveCard.new(
    Teams::Cards::TextBlock.new("Service status", size: "Large", weight: "Bolder"),
    Teams::Cards::TextBlock.new("All systems operational.", wrap: true)
  )

  ctx.post card
end
```

The official SDKs call plain message sending `send`. Ruby already defines `Object#send`, so `teams_rb` intentionally uses `post`. This is the one deliberate public API naming difference.

For Rails, define one `Teams::App` instance during boot and route `POST /api/messages` to `app.to_rack`. See [App basics](docs/essentials/app-basics.md#serving) for the Rack and Rails forms.

## Feature status

This table tracks supported Teams SDK capabilities. Deprecated upstream AI and devtools packages are intentionally excluded.

| Feature | Status | Guide |
|---|---|---|
| App setup and Rack/Rails integration | ✅ Done | [App basics](docs/essentials/app-basics.md) |
| Activity routing and middleware | ✅ Done | [Listening to activities](docs/essentials/on-activity.md) |
| App and error events | ✅ Done | [Listening to events](docs/essentials/on-event.md) |
| Typed activity models and raw payload access | ✅ Done | [Code basics](docs/getting-started/code-basics.md) |
| Posts, replies, updates, typing, formatting, mentions, citations, and labels | ✅ Done | [Sending messages](docs/essentials/sending-messages.md) |
| Proactive messaging and conversation references | ✅ Done | [Proactive messaging](docs/essentials/proactive-messaging.md) |
| Conversations, teams, meetings, users, and bot sign-in APIs | ✅ Done | [API client](docs/essentials/api-client.md) |
| Adaptive Cards | ✅ Done | [Adaptive Cards](docs/in-depth-guides/adaptive-cards.md) |
| Dialogs | ✅ Done | [Dialogs](docs/in-depth-guides/dialogs.md) |
| Message extensions | ✅ Done | [Message extensions](docs/in-depth-guides/message-extensions.md) |
| Streaming responses | ✅ Done | [Streaming](docs/in-depth-guides/streaming.md) |
| OAuth user authentication | ✅ Done | [User authentication](docs/in-depth-guides/user-authentication.md) |
| Microsoft Graph | ✅ Done | [Microsoft Graph](docs/essentials/graph.md) |
| Tabs and remote functions | ✅ Done | [Tabs and remote functions](docs/in-depth-guides/tabs.md) |
| Feedback | ✅ Done | [Feedback](docs/in-depth-guides/feedback.md) |
| Message reactions | ✅ Done | [Message reactions](docs/in-depth-guides/message-reactions.md) |
| Meeting events and notifications | ✅ Done | [Meeting events](docs/in-depth-guides/meeting-events.md) |
| Inbound authentication and bot tokens | ✅ Done | [App authentication](docs/essentials/app-authentication.md) |
| Sovereign cloud support | ✅ Done | [Sovereign clouds](docs/essentials/sovereign-cloud.md) |
| Logging and observability | ✅ Done | [Observability](docs/in-depth-guides/observability.md) |

## Documentation

- [Getting started](docs/getting-started/README.md) — quickstart, code basics, and running in Teams
- [Essentials](docs/essentials/README.md) — app setup, activities, sending, proactive messaging, API clients, authentication, and Graph
- [In-depth guides](docs/in-depth-guides/README.md) — cards, dialogs, extensions, streaming, user authentication, tabs, and events
- [Examples](examples/README.md) — runnable Rack apps for common SDK features
- [Changelog](CHANGELOG.md) — release history

## Development

Install dependencies and run the Minitest suite:

```sh
bundle install
bundle exec rake test
```

The gem is self-contained. Regenerating the typed Adaptive Card classes requires a sibling checkout of Microsoft's Python SDK; see the [Adaptive Cards guide](docs/in-depth-guides/adaptive-cards.md#regenerating).

## Questions and issues

Use [GitHub Issues](https://github.com/bavmind/teams_rb/issues) for bug reports and feature requests.

## License

`teams_rb` is available under the [MIT License](LICENSE).
