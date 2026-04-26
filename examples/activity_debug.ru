# frozen_string_literal: true

require "bundler/setup"
require "teams"

teams = Teams::App.new

teams.on_message do |ctx|
  ctx.typing

  activity = ctx.activity
  ref = ctx.ref

  client_info = activity.raw
    .fetch("entities", [])
    .find { |entity| entity["type"] == "clientInfo" } || {}

  tenant_id =
    ref.conversation.tenantId ||
    activity.raw.dig("channelData", "tenant", "id")

  ctx.reply Teams::Api::MessageActivity.new(<<~MARKDOWN, text_format: "markdown")
    # Activity debug

    ## User

    - **Name:** #{ref.user.name}
    - **ID:** `#{ref.user.id}`
    - **Platform:** #{client_info["platform"]}
    - **Timezone:** #{client_info["timezone"] || activity.localTimezone}

    ## Conversation

    1. **Conversation ID:** `#{ref.conversation_id}`
    2. **Type:** `#{ref.conversation.conversationType}`
    3. **Tenant:** `#{tenant_id}`

    ## Message

    > #{activity.text.inspect}

    [Service URL](#{ref.service_url})
  MARKDOWN

  ctx.post "debug response sent"
end

run teams.to_rack
