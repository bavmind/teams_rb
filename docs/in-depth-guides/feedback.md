# Feedback

Add thumbs up/down feedback buttons to a bot message — the standard way to collect quality signals on AI answers.

## Requesting feedback

```ruby
ctx.post Teams::Api::MessageActivity.new("Here's my answer.")
  .add_ai_generated
  .add_feedback
```

`add_feedback` enables the default feedback UI on the message. Teams renders the thumbs on hover; when a user submits feedback, your bot receives a `message/submitAction` invoke.

## Handling submissions

```ruby
teams.on_message_submit_feedback do |ctx|
  value = ctx.activity.value.raw
  FeedbackRecord.create!(
    reply_to: ctx.activity.raw["replyToId"],        # the message being rated
    reaction: value.dig("actionValue", "reaction"),  # "like" / "dislike"
    text: value.dig("actionValue", "feedback")       # free-text, JSON-encoded by some clients
  )
  nil
end
```

The rated message's id arrives as the invoke's `replyToId` — store your messages' `SentActivity#id`s if you need to join feedback back to content. `on_message_submit` (without the filter) catches every `message/submitAction` invoke, matching the TypeScript/Python route pair.
