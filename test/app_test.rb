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
end
