# frozen_string_literal: true

require "bundler/setup"
require "teams"

teams = Teams::App.new

teams.on_message(/^remember\b/i) do |ctx|
  ctx.storage.set("last_conversation_reference", ctx.ref.to_h)
  ctx.reply "Stored this conversation reference."
end

teams.on_message(/^notify\b/i) do |ctx|
  stored_reference = ctx.storage.get("last_conversation_reference")

  unless stored_reference
    ctx.reply "No stored conversation reference yet. Send `remember` first."
    next
  end

  ref = Teams::Api::ConversationReference.from_h(stored_reference)
  teams.post(
    ref.conversation_id,
    "Proactive post using a restored conversation reference.",
    service_url: ref.service_url
  )

  ctx.reply "Sent a proactive post to the stored conversation."
end

teams.on_message do |ctx|
  ctx.reply "Send `remember` to store ctx.ref, then `notify` to post using the stored reference."
end

run teams.to_rack
