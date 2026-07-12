# The API client

`teams.api` (also `ctx.api`) is the low-level Bot Framework client, structured like the other SDKs' API hub. Higher-level helpers (`ctx.reply`, `teams.post`, `ctx.sign_in`) route through it; use it directly when you need the raw surface.

## Conversations

```ruby
api.conversations.create(members:, tenant_id:, activity: nil, channel_data: nil)  # => ConversationResource
api.conversations.create_activity(conversation_id, activity)
api.conversations.reply_to_activity(conversation_id, activity_id, activity)
api.conversations.update_activity(conversation_id, activity_id, activity)
api.conversations.delete_activity(conversation_id, activity_id)

# targeted (single-recipient) variants
api.conversations.create_targeted_activity(conversation_id, activity)
api.conversations.update_targeted_activity(conversation_id, activity_id, activity)
api.conversations.delete_targeted_activity(conversation_id, activity_id)

# members — typed Teams::Api::Account results, aadObjectId normalized
api.conversations.get_members(conversation_id)
api.conversations.get_member_by_id(conversation_id, member_id)
api.conversations.get_paged_members(conversation_id, page_size: 200, continuation_token: nil)  # => PagedMembersResult
api.conversations.get_activity_members(conversation_id, activity_id)

# reactions
api.conversations.add_reaction(conversation_id, activity_id, "like")
api.conversations.delete_reaction(conversation_id, activity_id, "like")
```

For large rosters use `get_paged_members` and feed `continuation_token` back until it returns `nil`.

## Teams and meetings

```ruby
api.teams.get_by_id(team_id)                       # => TeamDetails
api.teams.get_conversations(team_id)               # => [ChannelInfo] — the team's channels

api.meetings.get_by_id(meeting_id)                 # => MeetingInfo
api.meetings.get_participant(meeting_id, aad_object_id, tenant_id)  # => MeetingParticipant
api.meetings.send_notification(meeting_id, { value: { recipients: [aad_object_id], surfaces: surfaces } })
```

`send_notification` returns `nil` when every recipient succeeded (202) and a `MeetingNotificationResponse` with per-recipient failures on partial success (207).

## Users and bot sign-in

The token-service clients behind [user authentication](../in-depth-guides/user-authentication.md):

```ruby
api.users.get_token(user_id:, connection_name:, channel_id: nil, code: nil)     # => TokenResponse
api.users.get_token_status(user_id:, channel_id:)                              # => [TokenStatus]
api.users.sign_out(user_id:, connection_name:, channel_id:)
api.users.exchange_token(user_id:, connection_name:, channel_id:, exchange_request:)
api.users.get_aad_tokens(user_id:, connection_name:, resource_urls:, channel_id:)

api.bots.sign_in.get_url(state:)        # => String
api.bots.sign_in.get_resource(state:)   # => SignInUrlResponse
```

## Errors

Failed requests raise `Teams::HttpError` with `status`, `headers`, `body` (parsed JSON when possible, raw string otherwise), and the request. Streaming sends additionally classify their 403s into typed stream errors ([Streaming](../in-depth-guides/streaming.md)).
