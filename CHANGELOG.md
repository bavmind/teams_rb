# Changelog

All notable changes to this project are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.1.0] - 2026-11-05

### Added

- `ctx.stream.update(text, text_format:)` sets the text format of an informative update, matching the TypeScript, Python, and .NET SDKs
- Receiving files: `ctx.files` lists the inbound activity's uploaded files (`list`/`first`) as lazy `Files::IncomingFile` handles with `download` (a `Files::DownloadedFile` snapshot), `text`, `save_as`, and `stream`; downloads are plain GETs with no bot token, following redirects only over HTTPS. Typed `Teams::FileError` subclasses: `FileUrlExpiredError` (`reason` `first_fetch`/`reread`) and `FileScopeNotSupportedError`. Adds `Api::FileDownloadInfo` and `Api::FILE_DOWNLOAD_INFO_CONTENT_TYPE`. Matches the TypeScript, Python, and .NET SDKs
- Agentic users receive files in personal chats, group chats, and channels: files that arrive with only a `content_url` are read through Microsoft Graph `/shares` with the agent's own token (never the app's), with `FileCredentialError` (no usable Graph credential, detected before the request; `actor`, `cause_detail`) and `FileAccessError` (refused by storage; `status`, `actor`, `details`). Matches the TypeScript, Python, and .NET SDKs
- Pasted inline images are listed by `ctx.files` with `attachment_style` `"inlineImage"` (named from the message's HTML format hint; downloads report the format the bytes actually are), read from the Bot API with the turn's token and only under the activity's service URL; `list`/`first` accept `attachment_style:` to filter. Adds `InlineImageTransformationError` (415) and `InlineImageAccessError` (401/403). Matches the TypeScript, Python, and .NET SDKs
- Per-turn state (opt-in `state:` App option, `true` or `State::StateOptions`): `ctx.state.conversation` and `ctx.state.user` are Hash-like `State::TurnState` scopes loaded before the handlers and saved after the turn (also when a handler raised) only when their content changed, including nested changes; emptied scopes are deleted, `ctx.state.delete` removes both, and the state is sealed after the turn (`State::TurnStateSealedError`). Stored as JSON under percent-encoded `{prefix}:conv:{conversationId}` / `{prefix}:user:{conversationId}:{userId}` keys in the app's storage or a dedicated one. Matches the TypeScript, Python, and .NET SDKs
- Multiple OAuth connections: `app.add_oauth_flow(name, oauth_card_text:, sign_in_button_text:)` registers an `OAuth::Flow` (case-insensitive, unique names; `app.get_oauth_flow` looks one up) with connection-bound `sign_in`, `sign_out`, `get_token`, `signed_in?`, and per-flow `on_sign_in`/`on_sign_in_failure` handlers; `app.on_oauth_sign_in_failure` receives an `OAuth::SignInFailureEvent`; `ctx.get_user_token(connection_name:)` and `ctx.get_connection_status`. Registering a flow enables per-turn state unless `state:` was set. Matches the TypeScript, Python, and .NET SDKs
- OAuth callbacks route to their registered flow: `ctx.sign_in` records the pending sign-in (in per-turn state, or a bounded process-local cache when state is off), token exchanges reach the flow they name, `signin/verifyState` probes pending flows, then registered flows, then the default connection, and `signin/failure` is attributed to the pending silent-SSO sign-in (or reported to every flow with `connection_name` `nil` when it cannot be). Terminal Token Service errors notify the flow's failure handlers (`code` `tokenservice.http_<status>`). Matches the TypeScript, Python, and .NET SDKs
- Microsoft Purview sensitivity labels: `Api::SensitivityUsageInfo` (`at_id` label id sent as `@id`, optional `name`/`description`/`position`, `at_type` defaulting to `CreativeWork`), `add_sensitivity_label(label)` writing it to the root message entity (replacing any earlier label), and citation `usage_info:` accepting it (citation usage info now defaults `@type` to `CreativeWork`). Matches the TypeScript, Python, and .NET SDKs

### Changed

- Targeted sends are no longer rejected by the SDK in 1:1 (personal) conversations; the Teams service decides whether a targeted message is valid (a plain 1:1 bot chat answers 400 `BadArgument`), matching the same change in the TypeScript, Python, and .NET SDKs
- Teams no longer supports stopping a stream, so stream cancellation handling is removed: a 403 mentioning cancellation is a `TerminalStreamError` like any other terminal stream failure, emits after it keep working, and the streaming time limit is documented as ten minutes. Matches the TypeScript, Python, and .NET SDKs
- `signin/verifyState` answers 404 (instead of 412) when no connection accepts the code, and token-exchange deduplication now also holds across instances through conversation state, expires completed exchanges after five minutes, and answers an in-flight duplicate with 412 when the original exchange raised. Matches the TypeScript and Python SDKs
- `ctx.sign_in` falls through to the OAuth card only when the Token Service answers 404 (no token); other Token Service failures now raise instead of being treated as a signed-out user, matching the Python SDK
- Adaptive Card classes no longer serialize schema defaults for optional fields the caller never set (for example `theme`, `fillMode`, `horizontalAlignment`, `requires`), which roughly tripled payload size; `version` keeps its `1.5` default and explicitly set values, including `false`, still serialize. Regenerated from the same generator change in the TypeScript, Python, and .NET SDKs

### Deprecated

- `app.on_sign_in` is renamed `app.on_oauth_sign_in` (same block arguments): app-level OAuth events now carry the `on_oauth_` prefix, like `app.on_oauth_sign_in_failure`, which keeps them apart from the `on_signin_*` invoke routes. The old name still works and emits a deprecation warning.
- `HttpStream#canceled` always returns false, and `Teams::StreamCancelledError` is never raised
- `add_sensitivity_label(name, description:, pattern:)` with a label name string; it writes a name-only label without the Purview label id. Pass an `Api::SensitivityUsageInfo` instead

### Fixed

- `ctx.reply` quotes the inbound message only when its id is a plain numeric message id (digits, not all zeros). Invokes, card-button messages, and feedback carry service-generated ids such as `f:<guid>` that the service rejects as quote targets with 400, so `ctx.reply` failed in card, dialog, and feedback handlers; it now sends without a quote there, exactly like `ctx.post`. Matches the same fix in the TypeScript, Python, and .NET SDKs
- Streamed text chunks carry the `textFormat` of the last emitted message, so streamed extended markdown (task lists, strikethrough) no longer renders as plain markdown until the message closes. Matches the same fix in the TypeScript, Python, and .NET SDKs
- Targeted message updates no longer send `recipient` in the payload (the recipient of an existing targeted message cannot change; it only selects the targeted endpoint); the returned `SentActivity` still carries it. Matches the TypeScript and Python SDKs

### Security

- Entra-authenticated inbound activities are accepted only when the token was requested by the Agent 365 platform app: the caller app is read from `azp`, or from `appid` when `azp` is absent, and compared case-insensitively; tokens requested by any other client app are rejected with 401. Bot Framework tokens are unaffected. Matches the same fix in the TypeScript, Python, and .NET SDKs

## [2.0.3] - 2026-11-05

### Added

- `Api::AgenticIdentity` and agentic account fields (`agentic_user_id`, `agentic_app_id`, `agentic_app_blueprint_id`, `callback_uri`, plus an `agentic_identity` helper on `Api::Account`) for Agent 365 activities, matching the TypeScript, Python, and .NET SDKs
- Inbound activity validation now accepts Entra-issued agent tokens: validated against the token's own tenant (bounded per-tenant JWKS caching) with the same three audience forms; the Bot Framework service-token path and the remote-function validation path are unchanged. Entra inbound tokens carry no `serviceurl` claim, so that check applies only to service tokens
- `CloudEnvironment#agent_bot_scope` (`https://botapi.skype.com/.default`)
- `on_agent_lifecycle` plus per-variant routes (`on_agentic_user_identity_created`/`identity_updated`/`manager_updated`/`enabled`/`disabled`/`deleted`/`undeleted`/`workload_onboarding_updated`) for Agent 365 `agentLifecycle` events, discriminated on the activity's `valueType`, with value readers for the lifecycle payload fields
- Agentic operation (experimental): inbound activities addressed to an agentic user scope the whole turn — context, sends, and streaming — to that identity; `app.agentic_identity` builds identities for proactive work, `post`/`reply`/`update` accept `agentic_identity:`, and `Api::Client#for_agentic_identity` returns an identity-scoped client. Agentic tokens use the three-step Agent 365 exchange (blueprint assertion with `fmi_path`, agentic-app client assertion, user federated-identity grant)
- GitHub Actions CI runs the test suite and gem build for pull requests and pushes to main ([#11](https://github.com/bavmind/teams_rb/pull/11), thanks [@dblock](https://github.com/dblock))

### Changed

- Use the `jwt` gem (new runtime dependency, `~> 3.3`) for inbound JWT decoding, JWK import, RS256 verification, and standard claim validation instead of handwritten token parsing and RSA key construction ([#12](https://github.com/bavmind/teams_rb/pull/12), thanks [@dblock](https://github.com/dblock))
- Match the TypeScript SDK's signing-key cache defaults: cache up to five keys per JWKS endpoint for ten minutes, fetch uncached keys immediately without rate limiting or negative caching, and reject key-fetch failures as authentication errors ([#12](https://github.com/bavmind/teams_rb/pull/12), thanks [@dblock](https://github.com/dblock))
- Allow five minutes of clock tolerance for inbound JWT expiry and not-before validation, matching the TypeScript, Python, and .NET SDKs ([#12](https://github.com/bavmind/teams_rb/pull/12), thanks [@dblock](https://github.com/dblock))

### Fixed

- Recover from signing-key rotation without restarting the bot instead of caching the first JWKS document indefinitely ([#14](https://github.com/bavmind/teams_rb/issues/14), [#12](https://github.com/bavmind/teams_rb/pull/12), thanks [@dblock](https://github.com/dblock))
- Avoid blocking cached signing-key validation behind slow JWKS or discovery requests while preserving coordinated successful cache misses ([#12](https://github.com/bavmind/teams_rb/pull/12), thanks [@dblock](https://github.com/dblock))
- Duplicate `signin/tokenExchange` invokes are deduplicated on the exchange id: each Teams client (desktop, web, mobile) rendering the OAuth card attempts its own silent exchange, and previously each successful one fired `on_sign_in`. Now only the first runs the exchange; duplicates answer 200 without re-emitting, an in-flight duplicate waits for the first result, and failed exchanges are not marked so retries still work. Follows the same fix in the TypeScript SDK (.NET already deduplicated)

## [2.0.2] - 2026-08-06

### Added

- `activity.channel_data.app` exposes the app info Teams delivers on inbound activities (`Teams::Api::AppInfo` with `id` and `version`), matching the `channelData.app` field the TypeScript, Python, and .NET SDKs model
- `dangerously_allow_unauthenticated_requests:` App option and the `DANGEROUSLY_ALLOW_UNAUTHENTICATED_REQUESTS` environment variable replace `skip_auth:` for disabling inbound validation, following the same rename in the TypeScript, Python, and .NET SDKs
- `on_card_search` routes `application/search` invokes (Adaptive Card dynamic typeahead `Input.ChoiceSet`), with `Api::SearchResponse`/`Api::SearchInvokeResult` for the response and `query_text`/`query_options`/`kind`/`dataset` readers on the activity value
- `on_conversation_update` plus named channel/team lifecycle routes (`on_channel_created`/`deleted`/`renamed`/`restored`, `on_team_archived`/`deleted`/`hard_deleted`/`renamed`/`restored`/`unarchived`) matched on `channelData.eventType`, following the route family the TypeScript, Python, and .NET SDKs share

### Changed

- Replies now POST to the conversation's base activities collection, carrying the reply semantics only in the body's `replyToId`; the redundant activity-id path segment is gone, matching the TypeScript, Python, and .NET clients
- `ctx.sign_in` in group chats and channels now sends the OAuth card into the conversation as a targeted message visible only to the requesting user, instead of creating a 1:1 chat and posting a notice into the group; channels omit the token exchange resource so the sign-in button renders (silent SSO is not supported in channel scope). Follows the same change in the Python and .NET SDKs

### Deprecated

- `skip_auth:` still works as an alias for `dangerously_allow_unauthenticated_requests:` but emits a deprecation warning

### Fixed

- Streamed activities (typing chunks, the final message, and the timed-out in-place update) now carry `replyToId` referencing the inbound activity, threading them under the triggering message like the TypeScript SDK (restores Bot Framework v1 behavior)

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

[Unreleased]: https://github.com/bavmind/teams_rb/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/bavmind/teams_rb/compare/v2.0.3...v2.1.0
[2.0.3]: https://github.com/bavmind/teams_rb/compare/v2.0.2...v2.0.3
[2.0.2]: https://github.com/bavmind/teams_rb/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/bavmind/teams_rb/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/bavmind/teams_rb/releases/tag/v2.0.0
