# Message extensions

Message extensions (compose extensions) add search boxes, action commands, and link unfurling to the Teams compose area. The commands are declared in the app manifest; the SDK routes the `composeExtension/*` invokes to named handlers whose return values become the invoke response.

> The manifest commands must be added in the classic Developer Portal view or the app package editor — the new Developer Portal UI currently lacks the message-extension commands editor.

## Search commands

A search box in the compose area. Return a `MessagingExtensionResponse` wrapping a result list; each attachment can carry a preview card:

```ruby
teams.on_message_ext_query do |ctx|
  query = ctx.activity.value.parameters.find { |p| p["name"] == "searchQuery" }&.dig("value")
  attachments = Item.search(query).map do |item|
    Teams::Api::MessagingExtensionAttachment.new(
      content_type: "application/vnd.microsoft.card.adaptive",
      content: item.to_card,
      preview: { "contentType" => "application/vnd.microsoft.card.thumbnail",
                 "content" => { "title" => item.title } }
    )
  end

  Teams::Api::MessagingExtensionResponse.new(
    Teams::Api::MessagingExtensionResult.new(type: "result", attachment_layout: "list", attachments: attachments)
  )
end
```

`on_message_ext_select_item` handles clicking a result when you return lightweight items and expand on selection.

## Action commands

An action command opens a dialog (via `fetchTask`) and then handles the submission — returning a `MessagingExtensionActionResponse`, which reuses the [dialog](dialogs.md) task-module responses:

```ruby
teams.on_message_ext_open do |ctx|
  Teams::Api::MessagingExtensionActionResponse.new(
    task: Teams::Api::TaskModuleContinueResponse.new(
      Teams::Api::TaskModuleTaskInfo.new(title: "Create", card: create_form_card)
    )
  )
end

teams.on_message_ext_submit do |ctx|
  item = Item.create!(title: ctx.activity.value.data["title"])
  Teams::Api::MessagingExtensionActionResponse.new(
    compose_extension: Teams::Api::MessagingExtensionResult.new(
      type: "result", attachment_layout: "list",
      attachments: [Teams::Api::MessagingExtensionAttachment.new(
        content_type: "application/vnd.microsoft.card.adaptive", content: item.to_card
      )]
    )
  )
end
```

## Link unfurling

When a user pastes a URL from a domain your manifest registers, Teams sends a `composeExtension/queryLink` invoke — return a card preview for it:

```ruby
teams.on_message_ext_query_link do |ctx|
  url = ctx.activity.value.raw["url"]
  Teams::Api::MessagingExtensionResponse.new(
    Teams::Api::MessagingExtensionResult.new(
      type: "result", attachment_layout: "list",
      attachments: [Teams::Api::MessagingExtensionAttachment.new(
        content_type: "application/vnd.microsoft.card.adaptive", content: unfurl_card(url)
      )]
    )
  )
end
```

## All routes

`on_message_ext_query`, `on_message_ext_select_item`, `on_message_ext_submit`, `on_message_ext_open`, `on_message_ext_query_link`, `on_message_ext_anon_query_link`, `on_message_ext_query_settings_url`, `on_message_ext_setting`, `on_message_ext_card_button_clicked` — the same nine the TypeScript and Python SDKs expose. The inbound command and parameters read from `ctx.activity.value` (`command_id`, `parameters`, `data`).
