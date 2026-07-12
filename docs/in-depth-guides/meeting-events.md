# Meeting events

When a bot is installed in a meeting chat, Teams posts event activities as the meeting starts and ends.

```ruby
teams.on_meeting_start do |ctx|
  v = ctx.activity.value
  ctx.post "#{v.title} started at #{v.start_time}"
end

teams.on_meeting_end do |ctx|
  ctx.post "Meeting ended at #{ctx.activity.value.end_time}"
end
```

The event value is available on `ctx.activity.value`, with readers matching the wire fields (which Teams sends PascalCase):

| Reader | Field | Notes |
|---|---|---|
| `id` | `Id` | Base64-encoded meeting id |
| `title` | `Title` | Meeting title |
| `meeting_type` | `MeetingType` | e.g. `"Scheduled"` |
| `join_url` | `JoinUrl` | Join link (start event) |
| `start_time` | `StartTime` | UTC timestamp (start event) |
| `end_time` | `EndTime` | UTC timestamp (end event) |

For meeting details and participant lookup outside events, use the [meetings API client](../essentials/api-client.md#teams-and-meetings).
