# Changelog

All notable changes to this project are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.0.1] - 2026-07-13

### Fixed

- `ctx.user_graph` now caches per connection name; requesting a different `connection_name:` returns a client for that connection instead of the first one fetched
- Remote function handlers returning `nil` now serialize as `{}`, keeping function responses valid JSON for `fetch(...).json()` callers
- Stream sequence/id updates are written under the stream mutex so `close` reliably observes the assigned stream id on non-GIL Ruby implementations
- Documented (in code) that the group-chat sign-in notice is deliberately posted to the group while the OAuth card goes to the 1:1 conversation, matching the TypeScript and Python SDKs

## [2.0.0] - 2026-07-13

Initial release. A Ruby-native port of the Microsoft Teams SDK concepts, verified
against the TypeScript, Python, and .NET SDKs and live-tested in Microsoft Teams.

Versioning starts at 2.0.0 to align with the Teams SDK v2 generation that this
project ports (TypeScript, Python, and C# all release as 2.x) — the same choice
the Python SDK made when it joined the family.

### Added

- Rack endpoint with inbound Bot Framework JWT validation (issuers, audiences, signature, `serviceurl` claim)
- Activity routing: messages (with patterns), message updates/edits, invokes, meeting events, middleware chain
- Sending: `post`, `reply`, `quote`, `update`, `typing`; text formats, mentions, sensitivity labels, citations, AI-generated labels, feedback; typed `SentActivity` returns
- Targeted (single-recipient) message support with automatic defaulting
- Proactive messaging with conversation references and conversation creation
- Streaming responses with background flushing, informative updates, stream events, typed stream errors, and reuse after close
- Adaptive Cards: all 112 element classes generated from the SDK card model, golden-tested for byte-identical serialization
- Dialogs (task modules): open/submit routing with dialog-id and action filters, multi-step forms
- Message extensions: all nine `composeExtension/*` routes with typed responses
- Full API client: conversations (activities, members, reactions, create), teams, meetings, user tokens, bot sign-in
- OAuth user sign-in: `ctx.sign_in`/`ctx.sign_out`, default token-exchange and verify-state handlers, `on_sign_in`/`on_error` events
- Microsoft Graph client with app identity (`teams.graph`) and user identity (`ctx.user_graph`)
- Remote functions callable from tabs with Entra token validation and client-context resolution
- Thread-safe token management, storage, and JWKS caching for multi-threaded Rack servers
- Documentation mirroring the official teams-sdk docs structure (getting started, essentials, in-depth guides)

[Unreleased]: https://github.com/bavmind/teams_rb/compare/v2.0.1...HEAD
[2.0.1]: https://github.com/bavmind/teams_rb/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/bavmind/teams_rb/releases/tag/v2.0.0
