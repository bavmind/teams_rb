# frozen_string_literal: true

require "bundler/setup"
require "teams"

teams = Teams::App.new

teams.on_message do |ctx|
  ctx.typing
  ctx.reply "reply: #{ctx.activity.text.inspect}"
  ctx.post "post: #{ctx.activity.text.inspect}"
end

run teams.to_rack
