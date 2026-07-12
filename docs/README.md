# teams_rb documentation

`teams_rb` is a Ruby-native port of the Microsoft Teams SDKs ([TypeScript](https://microsoft.github.io/teams-sdk/typescript/getting-started), [Python](https://microsoft.github.io/teams-sdk/python/getting-started), [C#](https://microsoft.github.io/teams-sdk/csharp/getting-started)). It preserves the Teams SDK concepts and wire behavior while using Ruby idioms for the public API, and these docs follow the same structure as the official SDK documentation.

> **Unofficial.** This is an independent, community-maintained project, not affiliated with, endorsed by, or sponsored by Microsoft. For the official SDKs, see [github.com/microsoft/teams-sdk](https://github.com/microsoft/teams-sdk).

## Getting started

1. [Quickstart](getting-started/quickstart.md) — install the gem and run your first echo bot
2. [Code basics](getting-started/code-basics.md) — the `App`, handlers, and the activity context
3. [Running in Teams](getting-started/running-in-teams.md) — registration, tunnel, and manifest

## Essentials

- [App basics](essentials/app-basics.md) — configuration, credentials, lifecycle
- [Listening to activities](essentials/on-activity.md) — routing, middleware, invokes, meeting events
- [Listening to events](essentials/on-event.md) — `on_sign_in`, `on_error`
- [Sending messages](essentials/sending-messages.md) — `post`, `reply`, `quote`, `update`, `typing`, formatting, mentions
- [Proactive messaging](essentials/proactive-messaging.md) — conversation references, creating conversations, threading
- [The API client](essentials/api-client.md) — `api.conversations`, `api.teams`, `api.meetings`, `api.users`, `api.bots`
- [App authentication](essentials/app-authentication.md) — inbound validation, bot tokens, the trust model
- [Sovereign clouds](essentials/sovereign-cloud.md) — government cloud endpoint routing
- [Microsoft Graph](essentials/graph.md) — app and user identity Graph clients

## In-depth guides

- [Adaptive Cards](in-depth-guides/adaptive-cards.md) — the generated card classes, actions, and submissions
- [Dialogs](in-depth-guides/dialogs.md) — task modules: opening, submissions, multi-step forms
- [Message extensions](in-depth-guides/message-extensions.md) — search commands, action commands, link unfurling
- [Streaming](in-depth-guides/streaming.md) — chunked responses, informative updates, stream events
- [User authentication](in-depth-guides/user-authentication.md) — OAuth sign-in, token exchange, Azure setup
- [Tabs and remote functions](in-depth-guides/tabs.md) — calling your bot backend from a tab with SSO
- [Feedback](in-depth-guides/feedback.md) — thumbs up/down on bot messages
- [Message reactions](in-depth-guides/message-reactions.md) — sending and receiving reactions
- [Meeting events](in-depth-guides/meeting-events.md) — meeting start/end
- [Observability](in-depth-guides/observability.md) — logging and middleware

## A note on naming

The Microsoft SDKs call their plain send operation `send`. Ruby already defines `Object#send` for dynamic dispatch, so `teams_rb` uses `post` — the one deliberate public API deviation. Everything else keeps the SDK family's shapes: Python-style snake_case method names, the same wire behavior, the same concepts.
