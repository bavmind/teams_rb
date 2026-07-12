# Proactive messaging

Sending outside an inbound request — from a job, a webhook, your product's backend.

## Conversation references

Inside a handler, `ctx.ref` is a `Teams::Api::ConversationReference` for the current conversation. Persist it, restore it later:

```ruby
# during a handler
ConversationRecord.create!(user: current_user, ref: ctx.ref.to_h)

# later, from a job
ref = Teams::Api::ConversationReference.from_h(record.ref)
teams.post(ref.conversation_id, "Your report is ready", service_url: ref.service_url)
```

The proactive surface on the app mirrors the SDK family:

```ruby
teams.post(conversation_id, activity)                 # send
teams.reply(conversation_id, activity_id, activity)   # threaded reply
teams.update(conversation_id, activity_id, activity)  # edit
```

`teams.reply` threads through the conversation id (`;messageid=...`), like TypeScript and Python.

## Messaging a user without a stored conversation

Create (or re-fetch) the 1:1 conversation — Teams returns the existing conversation when one exists for the same members:

```ruby
conversation = teams.api.conversations.create(
  members: [{ id: user_teams_id }],   # the user's Teams id ("29:...")
  tenant_id: tenant_id
)
teams.post(conversation.id, "Hello from your backend")
```

This is the standard SaaS pattern: notify any user who has the app installed, no prior chat required.

## Service URLs

Proactive sends default to the app's configured `SERVICE_URL`; pass `service_url:` from a stored reference to target the user's regional endpoint (references captured from real activities carry it).
