# Quickstart

Build and run your first Teams bot in Ruby.

## Prerequisites

- Ruby 4.0+
- A Microsoft 365 tenant with custom app upload enabled ([developer program](https://developer.microsoft.com/microsoft-365/dev-program) tenants work)
- A tunnel for local development ([Dev Tunnels](https://learn.microsoft.com/azure/developer/dev-tunnels/get-started), ngrok, or similar)

## Install

Add the SDK and a Rack server for this standalone example:

```ruby
# Gemfile
gem "teams_rb"
gem "puma"
```

```sh
bundle install
```

## Your first bot

Create a `config.ru`:

```ruby
require "teams"

teams = Teams::App.new

teams.on_message do |ctx|
  ctx.typing
  ctx.reply "echo: #{ctx.activity.text}"
end

run teams.to_rack
```

This example uses Puma; `teams_rb` itself does not require a server gem. Run it with:

```sh
CLIENT_ID=... CLIENT_SECRET=... TENANT_ID=... bundle exec puma -p 3978
```

The app listens for Teams activities on `POST /api/messages`, validates every inbound request against Microsoft's signing keys, and echoes any message back as a quoted reply.

The three environment variables come from your bot registration — [Running in Teams](running-in-teams.md) walks through creating one and connecting Teams to your locally running bot. For local experiments without credentials, `Teams::App.new(skip_auth: true)` disables inbound validation (never use it beyond local testing; the app logs a loud warning when you do).

## Where to go next

- [Code basics](code-basics.md) — what each part of this file does
- [Running in Teams](running-in-teams.md) — see it live inside the Teams client
