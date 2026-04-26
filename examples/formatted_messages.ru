# frozen_string_literal: true

require "bundler/setup"
require "teams"

teams = Teams::App.new

teams.on_message do |ctx|
  ctx.typing

  ctx.reply Teams::Api::MessageActivity.new(<<~MARKDOWN, text_format: "markdown")
    # Markdown response

    **You said:** `#{ctx.activity.text}`

    - plain strings work
    - markdown can format structured bot responses
    - xml is useful when Teams should preserve explicit line breaks
  MARKDOWN

  ctx.post Teams::Api::MessageActivity.new(<<~XML, text_format: "xml")
    <h3>XML response</h3>
    <p><b>Message:</b> #{ctx.activity.text}</p>
    <p>Line one<br>Line two</p>
  XML

  ctx.post "plain text response"
end

run teams.to_rack
