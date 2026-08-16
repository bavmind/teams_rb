# Agent 365 (experimental)

> Agent 365 support is experimental across the whole Teams SDK family, and the
> agentic token exchange in `teams_rb` has not yet been verified against a live
> Agent 365 tenant. Expect changes.

Agent 365 gives an app a *stacked identity*: the app registration acts as an
**agentic app blueprint** (its client id *is* the blueprint id), a tenant can
instantiate **agentic apps** from it, and each app can carry **agentic users**
— user-shaped Entra identities that appear in Teams like people.

## Inbound

Nothing to configure. When Teams delivers an activity to an agentic user, the
identity arrives on the activity's `recipient` account and the request carries
an Entra-issued token (accepted automatically alongside classic Bot Framework
tokens). The SDK scopes the whole turn to that identity — `ctx.post`, replies,
and streaming authenticate as the agent, not the app:

```ruby
teams.on_message do |ctx|
  identity = ctx.activity.recipient.agentic_identity
  ctx.log.info "acting as agentic user #{identity.agentic_user_id}" if identity
  ctx.reply "Hello from your agent"
end
```

## Lifecycle events

Teams reports agentic-user lifecycle changes as `agentLifecycle` events — see
[activity routing](../essentials/on-activity.md) for `on_agent_lifecycle` and
the per-variant routes.

## Proactive

Build the identity explicitly (the blueprint defaults to the app's client id,
the tenant to the configured credentials tenant) and pass it to the proactive
senders:

```ruby
identity = teams.agentic_identity(agentic_app_id: "...", agentic_user_id: "...")
teams.post(conversation_id, "Proactive hello from the agent", agentic_identity: identity)
```

Omitting `agentic_user_id` acts as the agentic app itself. There is no
fallback between identity kinds: if an agentic token cannot be acquired the
call fails rather than silently sending as the wrong identity.
