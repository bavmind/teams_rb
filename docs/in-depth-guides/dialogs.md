# Dialogs (task modules)

Dialogs are modal forms opened from a card action. A card button carrying `msteams: { type: "task/fetch" }` triggers a `task/fetch` invoke; the bot answers with the dialog content; the user's submission arrives as `task/submit`.

## Opening a dialog

The launcher card's action carries a reserved `dialog_id`:

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
```

Handle the open by returning the dialog:

```ruby
teams.on_dialog_open("simple_form") do |ctx|
  Teams::Api::TaskModuleResponse.new(
    Teams::Api::TaskModuleContinueResponse.new(
      Teams::Api::TaskModuleTaskInfo.new(
        title: "Simple form",
        card: {
          "type" => "AdaptiveCard", "version" => "1.4",
          "body" => [{ "type" => "Input.Text", "id" => "name", "label" => "Name", "isRequired" => true }],
          "actions" => [{ "type" => "Action.Submit", "title" => "Submit", "data" => { "action" => "submit_simple_form" } }]
        }
      )
    )
  )
end
```

`on_dialog_open(dialog_id)` matches only that dialog; `on_dialog_open` with no argument matches all. `TaskModuleTaskInfo` accepts `card:` (an `AdaptiveCard`, card hash, or attachment) **or** `url:` for a webpage dialog, plus `title:`, `height:`/`width:` (`"small"`/`"medium"`/`"large"` or pixels).

## Handling submissions

```ruby
teams.on_dialog_submit("submit_simple_form") do |ctx|
  name = ctx.activity.value.data["name"]
  ctx.post "Hi #{name}, thanks!"
  Teams::Api::TaskModuleResponse.new(Teams::Api::TaskModuleMessageResponse.new("Submitted"))
end
```

Return a `TaskModuleMessageResponse` to close the dialog with a message. `on_dialog_submit(action)` filters on the reserved `action` value in the submit data.

## Multi-step forms

Return another `TaskModuleContinueResponse` from a submit handler to advance to the next step — pass state forward in the next card's action data:

```ruby
teams.on_dialog_submit("step_1") do |ctx|
  name = ctx.activity.value.data["name"]
  Teams::Api::TaskModuleResponse.new(
    Teams::Api::TaskModuleContinueResponse.new(
      Teams::Api::TaskModuleTaskInfo.new(
        title: "Step 2",
        card: {
          "type" => "AdaptiveCard", "version" => "1.4",
          "body" => [{ "type" => "Input.Text", "id" => "email", "label" => "Email" }],
          "actions" => [{ "type" => "Action.Submit", "title" => "Finish",
                          "data" => { "action" => "step_2", "name" => name } }]
        }
      )
    )
  )
end
```
