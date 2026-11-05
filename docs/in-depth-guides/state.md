# State

Per-turn state stores conversation and user data across activities. It is loaded before your handlers run, saved automatically after the turn, and exposed as `ctx.state`.

## Setup

State is off by default (`ctx.state` is `nil`). Enable it with the `state:` option:

```ruby
teams = Teams::App.new(state: true)
```

`state: true` uses the app's `storage:` — the in-memory `Teams::Storage::MemoryStore` unless you pass another — which is fine for local development, but values are lost on restart and aren't shared across instances (the SDK logs a warning). See [Distributed state](#distributed-state).

## Reading and writing state

```ruby
teams.on_message do |ctx|
  ctx.state.conversation["count"] = ctx.state.conversation.fetch("count", 0) + 1
  ctx.state.user["name"] ||= ctx.activity.from.name

  ctx.reply "Message #{ctx.state.conversation["count"]} in this chat"
end
```

`ctx.state.conversation` is shared by everyone in the conversation; `ctx.state.user` is scoped to the sender **within that conversation** and is `nil` when the activity has no sender id. Both behave like a `Hash` (`[]`, `[]=`, `fetch`, `delete`, `key?`, `each`, `clear`, ...). Keys are strings — `state[:count]` reads and writes `"count"`.

Values must be JSON-serializable (`String`, `Integer`, `Float`, `true`/`false`, `nil`, `Array`, `Hash`); anything else raises when the turn is saved. Nested changes are detected, so `ctx.state.user["prefs"]["theme"] = "dark"` persists without reassignment, and nested hash keys come back as strings on the next turn.

A scope is written only when its content changed during the turn, and the save also runs when a handler raises. After the turn the state is sealed: don't keep it for background work — any later access raises `Teams::State::TurnStateSealedError`.

## Clearing state

Remove a value with `delete(key)` or empty a scope with `clear` (an emptied scope is deleted from storage at the end of the turn). To remove both scopes from storage immediately:

```ruby
ctx.state.delete
```

Values written after `delete` are saved normally at the end of the turn.

## Distributed state

Pass any storage object with `get(key)`, `set(key, value)`, and `delete(key)` — state values are JSON strings — through `Teams::State::StateOptions`:

```ruby
class RedisStateStorage
  def initialize(redis) = @redis = redis
  def get(key) = @redis.get(key)
  def set(key, value) = @redis.set(key, value, ex: 7 * 24 * 3600)
  def delete(key) = @redis.del(key)
end

teams = Teams::App.new(
  state: Teams::State::StateOptions.new(storage: RedisStateStorage.new(Redis.new), key_prefix: "ts")
)
```

Keys are `{key_prefix}:conv:{conversation id}` and `{key_prefix}:user:{conversation id}:{user id}`, with each id percent-encoded. Expiry and other storage policies belong to the storage provider; state has none by default.
