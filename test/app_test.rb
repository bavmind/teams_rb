# frozen_string_literal: true

require_relative "test_helper"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @api = FakeApi.new
    @teams = Teams::App.new(api: @api, skip_auth: true)
  end

  def app
    @teams.to_rack
  end

  def test_receives_message_and_replies
    @teams.on_message do |ctx|
      assert_instance_of Teams::Api::ConversationReference, ctx.ref
      assert_same ctx.ref, ctx.conversation_reference
      assert_equal "conversation-1", ctx.ref.conversation_id

      ctx.reply "echo: #{ctx.activity.text}"
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal "conversation-1", @api.sent.first[0]
    assert_equal "activity-1", @api.sent.first[1]["replyToId"]
    assert_includes @api.sent.first[1]["text"], "echo: hello"
    assert_includes @api.sent.first[1]["text"], "<blockquote"
    assert_equal({ "id" => "bot-1", "name" => "Bot" }, @api.sent.first[1]["from"])
    assert_equal({ "id" => "user-1", "name" => "User One", "aadObjectId" => "aad-1" }, @api.sent.first[1]["recipient"])
    assert_equal({ "id" => "conversation-1" }, @api.sent.first[1]["conversation"])
    assert_equal "msteams", @api.sent.first[1]["channelId"]
    assert_equal "https://smba.trafficmanager.net/teams", @api.sent.first[2]
  end

  def test_message_pattern_routes
    @teams.on_message(/hello/) { |ctx| ctx.post "matched" }
    @teams.on_message(/nope/) { |ctx| ctx.post "missed" }

    post "/api/messages", JSON.generate(teams_payload(text: "hello there")), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal 1, @api.sent.size
    assert_equal "matched", @api.sent.first[1]["text"]
  end

  def test_default_messaging_endpoint_is_api_messages
    assert_equal "/api/messages", @teams.messaging_endpoint

    post "/not-messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert_equal 404, last_response.status
  end

  def test_custom_messaging_endpoint
    @teams = Teams::App.new(api: @api, skip_auth: true, messaging_endpoint: "/bot/incoming")
    @teams.on_message { |ctx| ctx.post "custom route" }

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }
    assert_equal 404, last_response.status

    post "/bot/incoming", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }
    assert last_response.ok?
    assert_equal "custom route", @api.sent.first[1]["text"]
  end

  def test_messaging_endpoint_must_be_an_absolute_path
    error = assert_raises(ArgumentError) do
      Teams::App.new(api: @api, skip_auth: true, messaging_endpoint: "api/messages")
    end

    assert_equal "messaging_endpoint must be a non-empty path starting with '/'", error.message
  end

  def test_middleware_can_continue_to_next_handler
    events = []
    @teams.use do |ctx, nxt|
      events << "middleware:#{ctx.activity.type}"
      nxt.call
    end
    @teams.on_message { |_ctx| events << "message" }

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert_equal ["middleware:message", "message"], events
  end

  def test_rejects_invalid_json
    post "/api/messages", "{bad", { "CONTENT_TYPE" => "application/json" }

    assert_equal 400, last_response.status
  end

  def test_service_url_validation_rejects_untrusted_host
    post "/api/messages", JSON.generate(teams_payload(service_url: "https://evil.example.com/teams")), { "CONTENT_TYPE" => "application/json" }

    assert_equal 400, last_response.status
    assert_includes last_response.body, "serviceUrl host is not allowed"
  end

  def test_proactive_send
    @teams.post("conversation-2", "hello proactively")

    assert_equal "conversation-2", @api.sent.first[0]
    assert_equal "hello proactively", @api.sent.first[1]["text"]
    assert_equal({ "id" => "conversation-2" }, @api.sent.first[1]["conversation"])
    assert_equal "msteams", @api.sent.first[1]["channelId"]
    assert_equal "https://smba.trafficmanager.net/teams", @api.sent.first[2]
  end

  def test_proactive_send_requires_conversation_id
    reference = Teams::Api::ConversationReference.new(
      user: { "id" => "user-2" },
      bot: { "id" => "bot-2" },
      conversation: { "id" => "conversation-2" },
      channel_id: "msteams",
      service_url: "https://smba.trafficmanager.net/de/tenant-id"
    )

    error = assert_raises(ArgumentError) do
      @teams.post(reference, "hello by reference")
    end

    assert_equal "conversation_id must be a String", error.message
  end

  def test_proactive_reply_requires_activity_id_when_activity_is_provided
    error = assert_raises(ArgumentError) do
      @teams.reply("conversation-2", Teams::Api::MessageActivity.new("not an id"), "reply")
    end

    assert_equal "activity_id must be a String", error.message
  end

  def test_post_accepts_message_activity_with_text_format
    @teams.on_message do |ctx|
      ctx.post Teams::Api::MessageActivity.new("line 1<br>line 2", text_format: "xml")
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal "line 1<br>line 2", @api.sent.first[1]["text"]
    assert_equal "xml", @api.sent.first[1]["textFormat"]
  end

  def test_post_accepts_adaptive_card
    @teams.on_message do |ctx|
      ctx.post Teams::Cards::AdaptiveCard.new(Teams::Cards::TextBlock.new("Card body"))
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal "message", @api.sent.first[1]["type"]
    assert_equal "application/vnd.microsoft.card.adaptive", @api.sent.first[1]["attachments"].first["contentType"]
    assert_equal "Card body", @api.sent.first[1]["attachments"].first["content"]["body"].first["text"]
  end

  def test_reply_accepts_adaptive_card
    @teams.on_message do |ctx|
      ctx.reply Teams::Cards::AdaptiveCard.new(Teams::Cards::TextBlock.new("Reply card"))
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal "activity-1", @api.sent.first[1]["replyToId"]
    assert_equal "Reply card", @api.sent.first[1]["attachments"].first["content"]["body"].first["text"]
  end

  def test_post_accepts_hash_activity_escape_hatch
    @teams.on_message do |ctx|
      ctx.post({ "type" => "message", "text" => "**hello**", "textFormat" => "markdown" })
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal "**hello**", @api.sent.first[1]["text"]
    assert_equal "markdown", @api.sent.first[1]["textFormat"]
  end

  def test_proactive_reply_sets_reply_to_id
    @teams.reply("conversation-2", "activity-2", "thread reply")

    assert_equal "conversation-2", @api.sent.first[0]
    assert_equal "activity-2", @api.sent.first[1]["replyToId"]
    assert_equal "thread reply", @api.sent.first[1]["text"]
  end

  def test_typing_sends_without_reply_to_id
    @teams.on_message { |ctx| ctx.typing }

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal "typing", @api.sent.first[1]["type"]
    refute @api.sent.first[1].key?("replyToId")
    assert_empty @api.replies
  end

  def test_handler_errors_return_controlled_500
    @teams.on_message { raise "boom" }

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert_equal 500, last_response.status
    assert_includes last_response.body, "Internal server error"
  end

  def test_auth_is_required_by_default
    @teams = Teams::App.new(api: @api, client_id: "client-id", client_secret: "secret", tenant_id: "tenant")
    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert_equal 401, last_response.status
  end

  def test_stream_emits_cumulative_typing_chunks_and_final_message
    @teams.on_message do |ctx|
      ctx.stream.emit "Hello"
      ctx.stream.emit ", world"
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal 3, @api.sent.size

    first = @api.sent[0][1]
    second = @api.sent[1][1]
    final = @api.sent[2][1]

    assert_equal "typing", first["type"]
    assert_equal "Hello", first["text"]
    assert_equal 1, first.dig("channelData", "streamSequence")
    assert_equal "streaming", first.dig("channelData", "streamType")
    assert_equal "streaminfo", first["entities"].first["type"]

    assert_equal "typing", second["type"]
    assert_equal "Hello, world", second["text"]
    assert_equal "sent-1", second["id"]
    assert_equal "sent-1", second.dig("channelData", "streamId")
    assert_equal 2, second.dig("channelData", "streamSequence")

    assert_equal "message", final["type"]
    assert_equal "Hello, world", final["text"]
    assert_equal "sent-1", final["id"]
    assert_equal "final", final.dig("channelData", "streamType")
    refute final.dig("channelData", "streamSequence")
    assert_equal({ "type" => "streaminfo", "streamId" => "sent-1", "streamType" => "final" }, final["entities"].first)
  end

  def test_stream_update_sends_informative_chunk_before_final_message
    @teams.on_message do |ctx|
      ctx.stream.update "Thinking..."
      ctx.stream.emit "Hello"
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal 3, @api.sent.size

    informative = @api.sent[0][1]
    chunk = @api.sent[1][1]
    final = @api.sent[2][1]

    assert_equal "typing", informative["type"]
    assert_equal "Thinking...", informative["text"]
    assert_equal "informative", informative.dig("channelData", "streamType")
    assert_equal 1, informative.dig("channelData", "streamSequence")

    assert_equal "typing", chunk["type"]
    assert_equal "Hello", chunk["text"]
    assert_equal 2, chunk.dig("channelData", "streamSequence")

    assert_equal "message", final["type"]
    assert_equal "Hello", final["text"]
  end

  def test_stream_update_without_message_does_not_send_final_message
    @teams.on_message do |ctx|
      ctx.stream.update "Thinking..."
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal 1, @api.sent.size
    assert_equal "typing", @api.sent.first[1]["type"]
    assert_equal "Thinking...", @api.sent.first[1]["text"]
  end
end
