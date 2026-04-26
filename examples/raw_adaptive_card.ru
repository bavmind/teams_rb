# frozen_string_literal: true

require "bundler/setup"
require "teams"

teams = Teams::App.new

teams.on_message do |ctx|
  ctx.typing

  card = {
    "type" => "AdaptiveCard",
    "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json",
    "version" => "1.6",
    "body" => [
      {
        "type" => "TextBlock",
        "size" => "Medium",
        "weight" => "Bolder",
        "text" => "Publish Adaptive Card Schema",
        "wrap" => true
      },
      {
        "type" => "ColumnSet",
        "columns" => [
          {
            "type" => "Column",
            "width" => "auto",
            "items" => [
              {
                "type" => "Image",
                "style" => "Person",
                "url" => "https://pbs.twimg.com/profile_images/3647943215/d7f12830b3c17a5a9e4afcc370e3a37e_400x400.jpeg",
                "altText" => "Matt Hidinger",
                "size" => "Small"
              }
            ]
          },
          {
            "type" => "Column",
            "width" => "stretch",
            "items" => [
              {
                "type" => "TextBlock",
                "weight" => "Bolder",
                "text" => "Matt Hidinger",
                "wrap" => true
              },
              {
                "type" => "TextBlock",
                "spacing" => "None",
                "text" => "Created {{DATE(2017-02-14T06:08:39Z,SHORT)}}",
                "isSubtle" => true,
                "wrap" => true
              }
            ]
          }
        ]
      },
      {
        "type" => "TextBlock",
        "text" => "Now that we have defined the main rules and features of the format, we need to produce a schema and publish it to GitHub. The schema will be the starting point of our reference documentation.",
        "wrap" => true
      },
      {
        "type" => "FactSet",
        "facts" => [
          { "title" => "Board:", "value" => "Adaptive Cards" },
          { "title" => "List:", "value" => "Backlog" },
          { "title" => "Assigned to:", "value" => "Matt Hidinger" },
          { "title" => "Due date:", "value" => "Not set" }
        ]
      }
    ],
    "actions" => [
      {
        "type" => "Action.ShowCard",
        "title" => "Set due date",
        "card" => {
          "type" => "AdaptiveCard",
          "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json",
          "version" => "1.6",
          "body" => [
            {
              "type" => "Input.Date",
              "id" => "dueDate"
            },
            {
              "type" => "Input.Text",
              "id" => "comment",
              "placeholder" => "Add a comment",
              "isMultiline" => true
            }
          ],
          "actions" => [
            {
              "type" => "Action.Submit",
              "title" => "OK"
            }
          ]
        }
      },
      {
        "type" => "Action.OpenUrl",
        "title" => "View",
        "url" => "https://adaptivecards.io"
      }
    ]
  }

  ctx.post Teams::Api::MessageActivity.new.add_card(card)
end

run teams.to_rack
