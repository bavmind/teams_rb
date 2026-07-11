# teams_rb

Ruby SDK for receiving and sending Microsoft Teams bot messages from Rack/Rails apps.

This first MVP targets the production message-bot path:

- Rack endpoint for Teams messages
- Inbound Teams request validation enabled by default
- Message routing with `on_message`
- Replies, updates, and proactive sends through the Teams API
- Faraday HTTP client
- Minitest test suite

Current live status: receiving a Teams message and replying through Bot Framework has been verified with a Dev Tunnel and Microsoft Teams install.

## Local Usage

From another Ruby app:

```ruby
gem "teams_rb", path: "../teams_rb"
```

Then:

```ruby
require "teams"

teams = Teams::App.new

teams.on_message do |ctx|
  ctx.typing
  puts ctx.ref.conversation_id
  ctx.reply "reply: #{ctx.activity.text.inspect}"
  ctx.post "post: #{ctx.activity.text.inspect}"
end

run teams.to_rack
```

Suggested action submit invokes use the SDK route name and expose the submitted payload through `ctx.activity.value`:

```ruby
teams.on_suggested_action_submit do |ctx|
  ctx.post "submitted: #{ctx.activity.value.to_h.inspect}"
end
```

Message update events fire when a user edits or restores a Teams message:

```ruby
teams.on_edit_message do |ctx|
  puts "edited text: #{ctx.activity.text}"
end

teams.on_undelete_message do |ctx|
  puts "restored text: #{ctx.activity.text}"
end
```

Reactions use the API client shape from the Microsoft SDKs:

```ruby
teams.api.conversations.add_reaction(conversation_id, activity_id, "like")
teams.api.conversations.delete_reaction(conversation_id, activity_id, "like")
```

To update a message later, keep the activity id returned from the original send:

```ruby
sent = teams.post(conversation_id, "We have 2 Free iPhones, ready to pick up. While supplies last")

teams.update(conversation_id, sent.fetch("id"), "Free phones gone now.")
# equivalent SDK-send style:
teams.post(conversation_id, Teams::Api::MessageActivity.new("Free phones gone now.").with_id(sent.fetch("id")))
# lower-level parity surface:
teams.api.conversations.update_activity(conversation_id, sent.fetch("id"), Teams::Api::MessageActivity.new("Free phones gone now."))
```

More Rack examples live in `examples/`.

The Teams messaging endpoint defaults to `/api/messages`, matching the TypeScript and Python SDK defaults. If your app needs another path, configure it on the app and register the same full URL with Teams:

```ruby
teams = Teams::App.new(messaging_endpoint: "/bot/incoming")
run teams.to_rack
```

Use `ctx.post` for a plain message in the conversation. The Microsoft Teams SDKs call this `send`, but Ruby already defines `Object#send` for dynamic dispatch, so this SDK uses `post` for the public Ruby API. Treat `post` as Ruby's spelling of SDK `send`: if the activity already has an `id`, it updates that activity instead of creating a new one. Use `ctx.reply` when you want Teams reply semantics: `replyToId` plus the Teams `quotedReply` entity and quote placeholder, matching the Microsoft SDK behavior. Use `ctx.update(activity_id, activity)` to replace a previous bot message in the current conversation.

`ctx.ref` returns a `Teams::Api::ConversationReference`, matching the Teams SDK concept used for the current conversation. The same object is also available as `ctx.conversation_reference`. Store `ctx.ref.to_h` from a validated inbound activity if you need to post, reply, or update later from a job, then restore it with `Teams::Api::ConversationReference.from_h` and pass its `conversation_id` and `service_url` to `teams.post` / `teams.reply` / `teams.update`.

To message a user without a stored conversation, create (or re-fetch) the 1:1 conversation first. Teams returns the existing conversation if one already exists for the same members:

```ruby
conversation = teams.api.conversations.create(
  members: [{ id: user_id }],   # the user's Teams/Bot Framework id, e.g. "29:..."
  tenant_id: tenant_id
)
teams.post(conversation.id, "Hello from your SaaS backend")
```

Conversation rosters come from the members APIs, which return `Teams::Api::Account` objects (with `aadObjectId` normalized, matching the other SDKs):

```ruby
teams.api.conversations.get_members(conversation_id)
teams.api.conversations.get_member_by_id(conversation_id, member_id)
teams.api.conversations.get_paged_members(conversation_id, page_size: 200)          # => Teams::Api::PagedMembersResult
teams.api.conversations.get_activity_members(conversation_id, activity_id)
```

Use `get_paged_members` for large rosters: pass the result's `continuation_token` back in until it returns `nil`.

Team and meeting lookups follow the same client shape:

```ruby
teams.api.teams.get_by_id(team_id)            # => Teams::Api::TeamDetails
teams.api.teams.get_conversations(team_id)    # => [Teams::Api::ChannelInfo] (the team's channels)
teams.api.meetings.get_by_id(meeting_id)      # => Teams::Api::MeetingInfo
teams.api.meetings.get_participant(meeting_id, aad_object_id, tenant_id)
teams.api.meetings.send_notification(meeting_id, { value: { recipients: [aad_object_id], surfaces: [{ surface: "meetingStage", contentType: "task", content: { ... } }] } })
```

`send_notification` returns `nil` when every recipient was notified (HTTP 202) and a `Teams::Api::MeetingNotificationResponse` with `recipients_failure_info` on partial success (HTTP 207).

For modeled Ruby object access, use snake_case field names:

```ruby
ctx.activity.service_url
ctx.activity.reply_to_id
ctx.activity.from.aad_object_id
ctx.activity.conversation.conversation_type
```

Raw payload access stays unchanged through `raw` / `to_h`:

```ruby
ctx.activity.raw["serviceUrl"]
ctx.activity.raw.dig("from", "aadObjectId")
```

Quoted replies use the same SDK concepts as TypeScript, Python, and .NET:

```ruby
ctx.reply "auto-quotes the inbound activity"
ctx.quote "message-id", "quotes a specific activity"

message = Teams::Api::MessageActivity.new
  .add_quote("message-id", "builder response")

quotes = ctx.activity.get_quoted_messages
```

For formatted text, use a message activity with `text_format`:

```ruby
ctx.post Teams::Api::MessageActivity.new("plain text", text_format: "plain")
ctx.post Teams::Api::MessageActivity.new("**markdown**", text_format: "markdown")
ctx.post Teams::Api::MessageActivity.new("line 1<br>line 2", text_format: "xml")
ctx.post Teams::Api::MessageActivity.new("extended markdown", text_format: "extendedmarkdown")
```

Teams delivers activities with at-least-once semantics, so a message can occasionally reach your bot twice. Like the other Teams SDKs, `teams_rb` does not deduplicate inbound activities; if a handler performs side effects that must not repeat, deduplicate by `ctx.activity.id`.

For a typing indicator, use `ctx.typing`. Teams renders it as an animated ellipsis in the chat. It accepts optional text for wire parity with the other Teams SDKs, but the Teams client does not display that text on a plain typing activity — for a visible status line, use `ctx.stream.update` instead:

```ruby
ctx.typing                        # animated ellipsis
ctx.stream.update("Thinking...")  # visible status line above the streamed response
```

Updating an activity replaces it entirely: Teams does not merge with the previous version, so metadata such as the AI-generated label, sensitivity label, citations, and mentions must be re-attached on every update or they disappear (verified live). For example:

```ruby
sent = ctx.post Teams::Api::MessageActivity.new("Thinking...").add_ai_generated
ctx.update sent.id, Teams::Api::MessageActivity.new("Final answer.").add_ai_generated
```

Every send returns a `Teams::Api::SentActivity` carrying the outbound activity merged with the server response, so the sent message id is always available:

```ruby
sent = ctx.reply("hello")
sent.id   # server-assigned activity id
sent.text # "hello"
sent.to_h # full merged activity hash
```

When the inbound message is targeted (visible only to the sender), `ctx.post` and `ctx.reply` automatically respond as targeted messages to that sender, matching the other Teams SDKs: the recipient is inferred, a `targetedMessageInfo` entity is attached for prompt preview, and the send routes through the targeted activity endpoints. Pass an explicit recipient to opt out, or send an explicitly targeted message from any handler:

```ruby
ctx.post Teams::Api::MessageActivity.new("Only for you").with_recipient(account, is_targeted: true)
```

Targeted messages are rejected in 1:1 (personal) chats, where every message is already private.

This repository is self-contained: the generated card classes and their golden fixtures are committed, so the gem and its test suite need nothing beyond Ruby. Regenerating the card classes requires a clone of Microsoft's Python SDK and [uv](https://docs.astral.sh/uv/); by default a checkout next to this repository is used, and `TEAMS_PY_PATH` points anywhere else:

```sh
bundle exec rake cards:generate
# or with a custom checkout location:
TEAMS_PY_PATH=/path/to/teams.py bundle exec rake cards:generate
```

The SDK-parity comparison workflow additionally uses sibling clones of `teams.ts` and `teams.net`, as described in the porting workspace's `AGENTS.md`.

The full Adaptive Card schema (112 typed classes) is available under `Teams::Cards`, generated from the Python SDK's card models and golden-tested to serialize identically. Cards serialize with the same defaults the other SDKs emit. Raw card JSON via `add_card(hash)` remains available as an escape hatch. Two live-verified gotchas: some card fields are server-side enums (for example `CodeBlock` `language:` — Teams rejects the whole message for values outside the enum), and a card `Action.Submit` arrives as a message activity with `nil` text, an ephemeral id, and the inputs in `value` — answer it with `ctx.post`, since quote-replying to the invisible submit activity is rejected by Teams.

For streamed responses, use `ctx.stream`:

```ruby
teams.on_message do |ctx|
  ctx.stream.update("Thinking...")
  ctx.stream.emit("Hello")
  ctx.stream.emit(", world")
end
```

The stream emits events: `on_chunk` fires with the `SentActivity` of every sent chunk, and `on_close` fires with the final `SentActivity` when the stream finalizes. Handlers persist across stream reuse:

```ruby
ctx.stream.on_chunk { |sent| logger.debug("chunk #{sent.id}") }
ctx.stream.on_close { |sent| MessageLog.record(sent.id) }
```

Emits are queued and flushed by a background thread, matching the TypeScript and Python streamers: rapid emits coalesce into fewer chunks (spaced to respect Teams rate limits), transient send failures retry with backoff, and `close` waits for the queue to drain before sending the final message. Emitting again after `ctx.stream.close` starts a new streamed message on the same stream. If Teams stops a stream, the SDK raises typed errors: `Teams::StreamCancelledError` when the user cancels (sets the sticky `canceled` flag and makes the next `emit` raise), and `Teams::StreamNotAllowedError` or `Teams::TerminalStreamError` for terminal streaming failures — chunk-send errors are recorded on the stream and surface when `close` sends the final message. A stream that exceeds the Teams two-minute streaming limit finalizes automatically by updating the streamed message in place. Note that a card-only stream (no text ever emitted) sends nothing, like the other SDKs: emit text chunks first, then `clear_text` and emit the card as the final message.

To mark a final message as AI-generated, use `add_ai_generated` on `MessageActivity`. This also works as the final streamed message metadata:

```ruby
teams.on_message do |ctx|
  ctx.stream.update("Thinking...")
  ctx.stream.emit("Hello")
  ctx.stream.emit("! I'm a friendly AI bot. ")
  ctx.stream.emit(Teams::Api::MessageActivity.new.add_ai_generated)
end
```

Dialogs (Teams task modules) open from a card action whose data carries `msteams: { type: "task/fetch" }`. Route them with `on_dialog_open` / `on_dialog_submit`; the reserved `dialog_id` and `action` data keys select specific handlers, matching the other SDKs. The handler's return value — a `Teams::Api::TaskModuleResponse` (or an equivalent hash) — becomes the invoke response Teams renders:

```ruby
teams.on_message(/^form$/i) do |ctx|
  ctx.post Teams::Api::MessageActivity.new.add_card(
    Teams::Cards::AdaptiveCard.new(
      Teams::Cards::TextBlock.new("Open the form"),
      actions: [Teams::Cards::SubmitAction.new(
        title: "Open",
        data: { "msteams" => { "type" => "task/fetch" }, "dialog_id" => "simple_form" }
      )]
    )
  )
end

teams.on_dialog_open("simple_form") do |ctx|
  Teams::Api::TaskModuleResponse.new(
    Teams::Api::TaskModuleContinueResponse.new(
      Teams::Api::TaskModuleTaskInfo.new(title: "Simple Form", card: dialog_card)
    )
  )
end

teams.on_dialog_submit("submit_simple_form") do |ctx|
  ctx.post "Hi #{ctx.activity.value.data["name"]}!"
  Teams::Api::TaskModuleResponse.new(Teams::Api::TaskModuleMessageResponse.new("Form was submitted"))
end
```

`TaskModuleTaskInfo` takes `card:` (an `AdaptiveCard`, card hash, or ready attachment — cards are wrapped into an attachment automatically) or `url:` for webpage dialogs, plus `title:`, `height:`/`width:` (`"small"`/`"medium"`/`"large"` or pixels), `fallback_url:`, and `completion_bot_id:`. Returning a `TaskModuleContinueResponse` from a submit handler chains multi-step dialogs; a `TaskModuleMessageResponse` shows a message and closes.

Message extensions (compose extensions) route the `composeExtension/*` invokes with the same handler names as the Python SDK: `on_message_ext_query`, `on_message_ext_select_item`, `on_message_ext_submit`, `on_message_ext_open` (fetchTask), `on_message_ext_query_link`, `on_message_ext_anon_query_link`, `on_message_ext_query_settings_url`, `on_message_ext_setting`, and `on_message_ext_card_button_clicked`. The commands themselves are declared in the Teams app manifest; query handlers return a `MessagingExtensionResponse`, action handlers a `MessagingExtensionActionResponse` (which can open a dialog via `task:`, reusing the task module responses):

```ruby
teams.on_message_ext_query do |ctx|
  query = ctx.activity.value.parameters.find { |p| p["name"] == "searchQuery" }&.dig("value")
  results = Item.search(query).map do |item|
    Teams::Api::MessagingExtensionAttachment.new(
      content_type: "application/vnd.microsoft.card.adaptive",
      content: item.to_card,
      preview: { "contentType" => "application/vnd.microsoft.card.thumbnail",
                 "content" => { "title" => item.title } }
    )
  end

  Teams::Api::MessagingExtensionResponse.new(
    Teams::Api::MessagingExtensionResult.new(type: "result", attachment_layout: "list", attachments: results)
  )
end

teams.on_message_ext_query_link do |ctx|
  card = unfurl(ctx.activity.value.raw["url"])
  Teams::Api::MessagingExtensionResponse.new(
    Teams::Api::MessagingExtensionResult.new(type: "result", attachment_layout: "list", attachments: [card])
  )
end
```

For @mentions, use `add_mention` on the outbound message and the mention readers on inbound activities:

```ruby
ctx.post Teams::Api::MessageActivity.new("ping ").add_mention(ctx.activity.from.to_h)

teams.on_message do |ctx|
  if ctx.activity.recipient_mentioned?
    ctx.reply "You said: #{ctx.activity.strip_mentions_text}"
  end
end
```

To mark a message with a content sensitivity label:

```ruby
ctx.post Teams::Api::MessageActivity.new("Q3 numbers...").add_sensitivity_label(
  "Confidential",
  description: "Internal use only"
)
```

The label is informational: Teams renders a shield icon whose popup shows the name in bold, the description underneath, and an automatic "Sensitivity set by {bot}" attribution. Name and description are free text. The optional `pattern:` (a schema.org DefinedTerm hash) is carried on the wire but not rendered by the Teams client. No enforcement or Microsoft Purview integration is attached.

For citations, include the matching inline position marker in the text and add the citation to the message activity. The optional citation `text:` must be a stringified Adaptive Card (it renders in a modal when the citation is clicked); passing plain prose makes Teams reject the whole message with `400 BadSyntax`:

```ruby
message = Teams::Api::MessageActivity.new("The policy allows this [1].")
  .add_ai_generated
  .add_citation(
    1,
    Teams::Api::CitationAppearance.new(
      name: "Policy Guide",
      abstract: "Relevant policy excerpt",
      url: "https://example.com/policy",
      icon: "PDF"
    )
  )

ctx.post message
```

Citation `name` and `abstract` are required. Teams expects `name` to be at most 80 characters and `abstract` to be at most 160 characters. Keywords are documented as limited to 3 items, each at most 28 characters.

To show Teams' built-in feedback controls on a message:

```ruby
ctx.post Teams::Api::MessageActivity.new("Was this helpful?").add_feedback
```

For a custom feedback dialog flow, use `custom`:

```ruby
ctx.post Teams::Api::MessageActivity.new("Was this helpful?").add_feedback("custom")
```

For Adaptive Cards, use `Teams::Cards` objects directly or wrap them in a message activity:

```ruby
card = Teams::Cards::AdaptiveCard.new(
  Teams::Cards::TextBlock.new("Create ticket", weight: "Bolder", size: "Large", wrap: true),
  Teams::Cards::TextInput.new(id: "title", label: "Title", is_required: true),
  actions: [
    Teams::Cards::SubmitAction.new(title: "Create", data: { action: "create_ticket" })
  ]
)

ctx.post card
ctx.reply card
ctx.post Teams::Api::MessageActivity.new.add_card(card)
```

## Configuration

`Teams::App.new` reads its configuration from the environment by default; every value can also be passed explicitly as a keyword argument:

| Env var | Keyword | Required | Purpose |
|---|---|---|---|
| `CLIENT_ID` | `client_id:` | production | The bot's Microsoft App ID. Used for bot token requests and to validate inbound JWT audiences. |
| `CLIENT_SECRET` | `client_secret:` | production | The bot's client secret for the client-credentials token flow. |
| `TENANT_ID` | `tenant_id:` | single-tenant bots | Entra tenant for bot tokens and tenant-issuer JWT validation. |
| `SERVICE_URL` | `service_url:` | no | Default Bot Framework service URL for proactive sends (defaults to `https://smba.trafficmanager.net/teams`). Inbound requests always use the service URL from the activity. |
| — | `skip_auth:` | no | Disables inbound request validation. Local development only. |
| — | `messaging_endpoint:` | no | Inbound path, defaults to `/api/messages`. |
| — | `logger:`, `storage:`, `cloud:` | no | Logger (defaults to stdout), state store (defaults to the in-memory store), and cloud environment for sovereign clouds. |

For local tests only:

```ruby
teams = Teams::App.new(skip_auth: true)
```

Production apps must provide `CLIENT_ID`, `CLIENT_SECRET`, and `TENANT_ID`. Without credentials the app logs a startup warning and rejects every inbound request unless `skip_auth: true` was set explicitly — the same behavior as the TypeScript, Python, and .NET SDKs.

## Rails

Define the app once (an initializer works well) and route the messaging endpoint to it:

```ruby
# config/initializers/teams_bot.rb
TEAMS_BOT = Teams::App.new

TEAMS_BOT.on_message do |ctx|
  ctx.reply "Hello from Rails"
end
```

```ruby
# config/routes.rb
post "/api/messages" => TEAMS_BOT.to_rack
```

Routing the exact path (rather than `mount`) keeps the request's full path intact, which the endpoint check relies on. If you prefer `mount`, mount at root — `mount TEAMS_BOT.to_rack => "/"` — and let the SDK's own endpoint matching answer 404 for everything else; register whichever full URL you chose with Teams.

Handlers run inside the web request, so treat them like controller actions: keep them fast, and push slow work (LLM calls, big queries) to a job, then deliver the result proactively with the stored conversation reference. Remember that Bot Framework delivers at-least-once — if a handler's side effect must not repeat, dedupe by `ctx.activity.id` before performing it:

```ruby
teams.on_message do |ctx|
  next if ProcessedActivity.exists?(activity_id: ctx.activity.id)
  ProcessedActivity.create!(activity_id: ctx.activity.id)

  answer = Assistant.answer(user: ctx.activity.from.aad_object_id, text: ctx.activity.text)
  ctx.stream.emit(answer)
end
```

## Local development

1. Register a bot (Microsoft's [Teams CLI](https://github.com/microsoft/teams-sdk) or the Developer Portal) and note the client id, client secret, and tenant id. Put them in `.env` as `CLIENT_ID`, `CLIENT_SECRET`, `TENANT_ID`.
2. Expose your local port with a persistent tunnel, e.g. Dev Tunnels: `devtunnel create teams-bot -a && devtunnel port create teams-bot -p 3978`, then `devtunnel host teams-bot`.
3. Set the bot's messaging endpoint to `https://<your-tunnel>/api/messages` in the bot registration, and install the app in Teams.
4. Run the app: `bundle exec rackup -p 3978 -o 0.0.0.0`. Inbound requests are JWT-validated with your real credentials — no `skip_auth` needed behind a tunnel.

If the tunnel URL is stable (Dev Tunnels URLs are), steps 1–3 are one-time setup.

## API reference

| Surface | Methods |
|---|---|
| Routing | `teams.on_message(pattern = nil)`, `on_message_update`, `on_edit_message`, `on_undelete_message`, `on_dialog_open(dialog_id = nil)`, `on_dialog_submit(action = nil)`, `on_message_ext_*` (nine composeExtension routes), `on_meeting_start`, `on_meeting_end`, `on_suggested_action_submit`, `on(type)` (escape hatch), `use` (middleware, `(ctx, next)`) |
| Context (`ctx`) | `activity`, `ref` / `conversation_reference`, `post`, `reply`, `quote(message_id, ...)`, `update(activity_id, ...)`, `typing(text = nil)`, `stream` (`emit`, `update`, `clear_text`, `close`, `on_chunk`, `on_close`), `api`, `storage`, `log` |
| Proactive (`teams`) | `post(conversation_id, activity)`, `reply(conversation_id, activity_id, activity)`, `update(conversation_id, activity_id, activity)`, `send_activity(reference, activity)` |
| API client (`teams.api`) | `conversations` (`create`, `create_activity`, `reply_to_activity`, `update_activity`, `delete_activity`, targeted variants, `get_members`, `get_member_by_id`, `get_paged_members`, `get_activity_members`, `add_reaction`, `delete_reaction`), `teams` (`get_by_id`, `get_conversations`), `meetings` (`get_by_id`, `get_participant`, `send_notification`) |
| Sends return | `Teams::Api::SentActivity` (outbound activity merged with the server response; `#id`, `#[]`, `#to_h`) |
| Auth | Inbound JWTs validated against Bot Framework/Entra issuers, the three audience forms, expiry/nbf, signature, and the `serviceurl` claim. Outbound bot tokens via client-credentials flow, cached with refresh skew. `AuthenticationError` → 401, `BadRequestError` → 400, handler errors → 500 (Bot Framework then redelivers). |
