# Listening to events

Beyond activity routes, the app emits two application-level events, registered with named methods (the Ruby counterpart of the TypeScript/Python event emitters).

## Sign-in

Fires whenever a user sign-in completes through the default OAuth handlers — both the silent token-exchange path and the interactive card path:

```ruby
teams.on_sign_in do |ctx, token_response|
  ctx.post "Welcome! You're signed in."
  # token_response.token is the user's access token for the
  # OAuth connection's scopes; ctx is the invoke's activity context
end
```

See [User authentication](../in-depth-guides/user-authentication.md) for the full flow.

## Errors

Fires when a default OAuth handler hits an unexpected failure, or when the Teams client reports a sign-in failure:

```ruby
teams.on_error do |error, activity|
  Honeybadger.notify(error, context: { activity_id: activity&.id })
end
```

Handler errors during normal activity processing are not routed here — they surface as 500 responses (and Bot Framework redelivery); log-based monitoring catches those via the app's error log line.
