# teams_rb — Teams SDK for Ruby

[![Gem Version](https://img.shields.io/gem/v/teams_rb)](https://rubygems.org/gems/teams_rb)
[![Documentation](https://img.shields.io/badge/docs-getting_started-blue)](docs/getting-started/README.md)

A Ruby-native port of the Microsoft Teams SDKs for building Teams bots and apps with Rack or Rails. It includes message routing, proactive messaging, the Bot Framework API client, typed Adaptive Cards, dialogs, message extensions, streaming, meetings, OAuth, Microsoft Graph, tabs, and remote functions.

`teams_rb` preserves the concepts and wire behavior of the official [TypeScript](https://microsoft.github.io/teams-sdk/typescript/getting-started), [Python](https://microsoft.github.io/teams-sdk/python/getting-started), and [C#](https://microsoft.github.io/teams-sdk/csharp/getting-started) SDKs while providing an idiomatic Ruby API. Inbound JWT validation and outbound bot token management are built in.

> **Unofficial.** `teams_rb` is an independent, community-maintained project. It is not affiliated with, endorsed by, or sponsored by Microsoft. The official Teams SDKs are developed by Microsoft at [github.com/microsoft/teams-sdk](https://github.com/microsoft/teams-sdk).

## Getting started

### Prerequisites

- Ruby 4.0 or newer
- A Microsoft 365 tenant where you can register a Teams app
- A public HTTPS tunnel for local development, such as [Dev Tunnels](https://learn.microsoft.com/azure/developer/dev-tunnels/get-started)

### Install

Add the gem to your `Gemfile`:

```ruby
gem "teams_rb"
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

Run the app with the credentials from your bot registration:

```sh
CLIENT_ID=... CLIENT_SECRET=... TENANT_ID=... bundle exec rackup -p 3978 -o 0.0.0.0
```

The bot receives Teams activities at `POST /api/messages`, validates each request, and replies to incoming messages.

### Connect it to Teams

1. Create and configure the bot with the [Teams CLI](https://www.npmjs.com/package/@microsoft/teams.cli), or use the [Teams Developer Portal](https://dev.teams.microsoft.com/apps) and enable the Microsoft Teams channel manually.
2. Expose port `3978` through your HTTPS tunnel.
3. Set the bot's messaging endpoint to `https://<your-tunnel>/api/messages`, install the app in Teams, and send it a message.

See [Running in Teams](docs/getting-started/running-in-teams.md) for the complete registration, tunnel, and installation walkthrough.

## Code basics

Use `ctx.post` to send a message to the conversation and `ctx.reply` for a Teams quoted reply:

```ruby
teams.on_message do |ctx|
  ctx.post "A message in the conversation"
  ctx.reply "A reply quoting your message"
end
```

The official SDKs call plain message sending `send`. Ruby already defines `Object#send`, so `teams_rb` intentionally uses `post`. This is the one deliberate public API naming difference.

For Rails, define one `Teams::App` instance during boot and route `POST /api/messages` to `app.to_rack`. See [App basics](docs/essentials/app-basics.md#serving) for the Rack and Rails forms.

## Feature status

| Feature | Status | Guide |
|---|---|---|
| App setup and Rack/Rails integration | ✅ Done | [App basics](docs/essentials/app-basics.md) |
| Activity routing and middleware | ✅ Done | [Listening to activities](docs/essentials/on-activity.md) |
| App and error events | ✅ Done | [Listening to events](docs/essentials/on-event.md) |
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

## Development

Install dependencies and run the Minitest suite:

```sh
bundle install
bundle exec rake test
```

Run the basic echo example:

```sh
bundle exec rackup examples/basic_echo.ru -p 3978
```

The gem is self-contained. Regenerating the typed Adaptive Card classes requires a sibling checkout of Microsoft's Python SDK; see the [Adaptive Cards guide](docs/in-depth-guides/adaptive-cards.md#regenerating).

## Questions and issues

Use [GitHub Issues](https://github.com/bavmind/teams_rb/issues) for bug reports and feature requests.

## License

`teams_rb` is available under the [MIT License](LICENSE).
