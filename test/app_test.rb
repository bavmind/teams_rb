# frozen_string_literal: true

require_relative "test_helper"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @log_output = StringIO.new
    @logger = Logger.new(@log_output)
    @api = FakeApi.new
    @teams = Teams::App.new(api: @api, skip_auth: true, logger: @logger)
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
    refute @api.sent.first[1].key?("replyToId")
    assert_equal %(<quoted messageId="activity-1"/> echo: hello), @api.sent.first[1]["text"]
    assert_equal(
      [{ "type" => "quotedReply", "quotedReply" => { "messageId" => "activity-1" } }],
      @api.sent.first[1]["entities"]
    )
    assert_equal({ "id" => "bot-1", "name" => "Bot" }, @api.sent.first[1]["from"])
    refute @api.sent.first[1].key?("recipient")
    refute @api.sent.first[1].key?("channelId")
    assert_equal({ "id" => "conversation-1" }, @api.sent.first[1]["conversation"])
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

  def test_activity_get_quoted_messages
    quotes = []

    @teams.on_message do |ctx|
      quotes = ctx.activity.get_quoted_messages
    end

    post "/api/messages", JSON.generate(quoted_teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal 1, quotes.length
    assert_equal "quoted-1", quotes.first.quoted_reply.message_id
    assert_equal "User Two", quotes.first.quoted_reply.sender_name
  end

  def test_default_messaging_endpoint_is_api_messages
    assert_equal "/api/messages", @teams.messaging_endpoint

    post "/not-messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert_equal 404, last_response.status
  end

  def test_custom_messaging_endpoint
    @teams = Teams::App.new(api: @api, skip_auth: true, messaging_endpoint: "/bot/incoming", logger: @logger)
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

  def test_sends_return_sent_activity_with_id
    proactive = @teams.post("conversation-2", "hello")

    assert_instance_of Teams::Api::SentActivity, proactive
    assert_equal "sent-1", proactive.id
    assert_equal "hello", proactive.text
    assert_equal "conversation-2", proactive.conversation_id

    results = []
    @teams.on_message do |ctx|
      results << ctx.post("from handler")
      results << ctx.reply("reply from handler")
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert(results.all? { |result| result.is_a?(Teams::Api::SentActivity) })
    assert(results.all?(&:id))
  end

  def test_proactive_send
    @teams.post("conversation-2", "hello proactively")

    assert_equal "conversation-2", @api.sent.first[0]
    assert_equal "hello proactively", @api.sent.first[1]["text"]
    assert_equal({ "id" => "conversation-2" }, @api.sent.first[1]["conversation"])
    refute @api.sent.first[1].key?("channelId")
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
    refute @api.sent.first[1].key?("replyToId")
    assert_equal "Reply card", @api.sent.first[1]["attachments"].first["content"]["body"].first["text"]
  end

  def test_quote_sends_reply_to_specific_message_id
    @teams.on_message do |ctx|
      ctx.quote "quoted-activity-1", "quoted reply"
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    refute @api.sent.first[1].key?("replyToId")
    assert_equal %(<quoted messageId="quoted-activity-1"/> quoted reply), @api.sent.first[1]["text"]
    assert_equal(
      [{ "type" => "quotedReply", "quotedReply" => { "messageId" => "quoted-activity-1" } }],
      @api.sent.first[1]["entities"]
    )
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

  def test_hash_activities_accept_symbol_keys
    @teams.on_message do |ctx|
      ctx.post({ type: "message", text: "symbols", channelData: { feedbackLoop: { type: "default" } } })
      ctx.stream.emit({ type: "message", text: "streamed symbols" })
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?

    plain = @api.sent.first[1]
    assert_equal "symbols", plain["text"]
    assert_equal({ "type" => "default" }, plain.dig("channelData", "feedbackLoop"))

    chunk = @api.sent[1][1]
    assert_equal "typing", chunk["type"]
    assert_equal "streamed symbols", chunk["text"]
    assert_equal "streaming", chunk.dig("channelData", "streamType")
  end

  def test_suggested_action_submit_handler
    values = []

    @teams.on_suggested_action_submit do |ctx|
      values << ctx.activity.value.to_h
      ctx.post "submitted: #{ctx.activity.value.to_h.fetch("choice")}"
    end

    post "/api/messages", JSON.generate(suggested_action_submit_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal [{ "choice" => "approve" }], values
    assert_equal "submitted: approve", @api.sent.first[1]["text"]
  end

  def test_suggested_action_submit_generic_route_alias
    events = []

    @teams.on("invoke") { |_ctx, nxt| events << "invoke"; nxt.call }
    @teams.on("suggested-action.submit") { |_ctx| events << "suggested-action.submit" }

    post "/api/messages", JSON.generate(suggested_action_submit_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal ["invoke", "suggested-action.submit"], events
  end

  def test_message_update_handler
    updates = []

    @teams.on_message_update do |ctx|
      updates << [ctx.activity.text, ctx.activity.channel_data.event_type]
    end

    post "/api/messages", JSON.generate(message_update_payload(text: "edited")), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal [["edited", "editMessage"]], updates
  end

  def test_edit_message_handler
    events = []

    @teams.on_message_update { |_ctx, nxt| events << "messageUpdate"; nxt.call }
    @teams.on_edit_message { |ctx| events << "edit:#{ctx.activity.text}" }

    post "/api/messages", JSON.generate(message_update_payload(text: "edited")), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal ["messageUpdate", "edit:edited"], events
  end

  def test_undelete_message_handler
    events = []

    @teams.on_undelete_message { |ctx| events << "undelete:#{ctx.activity.text}" }

    post "/api/messages", JSON.generate(message_update_payload(text: "restored", event_type: "undeleteMessage")), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal ["undelete:restored"], events
  end

  def test_message_update_generic_activity_type_route
    events = []

    @teams.on("messageUpdate") { |_ctx, nxt| events << "messageUpdate"; nxt.call }

    post "/api/messages", JSON.generate(message_update_payload(text: "edited")), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal ["messageUpdate"], events
  end

  def test_proactive_reply_threads_conversation_id
    @teams.reply("conversation-2", "1728640934763", "thread reply")

    assert_equal "conversation-2;messageid=1728640934763", @api.sent.first[0]
    refute @api.sent.first[1].key?("replyToId")
    assert_equal "thread reply", @api.sent.first[1]["text"]
  end

  def test_proactive_reply_requires_numeric_message_id
    error = assert_raises(ArgumentError) do
      @teams.reply("conversation-2", "activity-2", "thread reply")
    end

    assert_equal %(invalid message_id "activity-2": must be a non-zero numeric value), error.message
  end

  def test_to_threaded_conversation_id_strips_existing_thread_suffix
    assert_equal(
      "19:abc@thread.skype;messageid=456",
      Teams.to_threaded_conversation_id("19:abc@thread.skype;messageid=123", "456")
    )
  end

  def test_proactive_update_replaces_existing_activity
    @teams.update("conversation-2", "activity-2", "Free phones gone now.")

    assert_equal "conversation-2", @api.updates.first[0]
    assert_equal "activity-2", @api.updates.first[1]
    assert_equal "Free phones gone now.", @api.updates.first[2]["text"]
    assert_equal({ "id" => "conversation-2" }, @api.updates.first[2]["conversation"])
    refute @api.updates.first[2].key?("channelId")
    assert_equal "https://smba.trafficmanager.net/teams", @api.updates.first[3]
  end

  def test_post_updates_existing_activity_when_activity_has_id
    @teams.post("conversation-2", { "type" => "message", "id" => "activity-2", "text" => "updated" })

    assert_empty @api.sent
    assert_equal "conversation-2", @api.updates.first[0]
    assert_equal "activity-2", @api.updates.first[1]
    assert_equal "updated", @api.updates.first[2]["text"]
  end

  def test_post_updates_existing_message_activity_with_id
    activity = Teams::Api::MessageActivity.new("updated").with_id("activity-2")

    @teams.post("conversation-2", activity)

    assert_empty @api.sent
    assert_equal "activity-2", @api.updates.first[1]
    assert_equal "updated", @api.updates.first[2]["text"]
  end

  def test_context_update_replaces_existing_activity_in_current_conversation
    @teams.on_message do |ctx|
      ctx.update "assistant-activity-1", "Thanks for your feedback."
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal "conversation-1", @api.updates.first[0]
    assert_equal "assistant-activity-1", @api.updates.first[1]
    assert_equal "Thanks for your feedback.", @api.updates.first[2]["text"]
    assert_equal "https://smba.trafficmanager.net/teams", @api.updates.first[3]
  end

  def test_proactive_update_requires_activity_id
    error = assert_raises(ArgumentError) do
      @teams.update("conversation-2", Teams::Api::MessageActivity.new("not an id"), "update")
    end

    assert_equal "activity_id must be a String", error.message
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
      fast_stream(ctx.stream)
      ctx.stream.emit "Hello"
      # Wait for the first chunk to ship so the second emit lands in a
      # separate flush cycle, making the chunk boundary deterministic.
      wait_until { @api.sent.size == 1 }
      ctx.stream.emit ", world"
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal 3, @api.sent.size
    assert_equal 0, @api.updates.size

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
      fast_stream(ctx.stream)
      ctx.stream.update "Thinking..."
      ctx.stream.emit "Hello"
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal 3, @api.sent.size
    assert_equal 0, @api.updates.size

    informative = @api.sent[0][1]
    chunk = @api.sent[1][1]
    final = @api.sent[2][1]

    assert_equal "typing", informative["type"]
    assert_equal "Thinking...", informative["text"]
    assert_equal "informative", informative.dig("channelData", "streamType")
    assert_equal 1, informative.dig("channelData", "streamSequence")

    assert_equal "typing", chunk["type"]
    assert_equal "Hello", chunk["text"]
    assert_equal "streaming", chunk.dig("channelData", "streamType")
    assert_equal 2, chunk.dig("channelData", "streamSequence")

    assert_equal "message", final["type"]
    assert_equal "Hello", final["text"]
  end

  def test_stream_update_without_message_does_not_send_final_message
    @teams.on_message do |ctx|
      fast_stream(ctx.stream)
      ctx.stream.update "Thinking..."
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal 1, @api.sent.size
    assert_equal "typing", @api.sent.first[1]["type"]
    assert_equal "Thinking...", @api.sent.first[1]["text"]
  end

  def test_stream_final_message_can_add_ai_generated_label
    @teams.on_message do |ctx|
      fast_stream(ctx.stream)
      ctx.stream.emit "Hello"
      wait_until { @api.sent.size == 1 }
      ctx.stream.emit Teams::Api::MessageActivity.new.add_ai_generated
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    # The second flush cycle contains a message emit, so the accumulated
    # text ships again as a chunk before the final, like TypeScript/Python.
    assert_equal 3, @api.sent.size
    assert_equal 0, @api.updates.size

    final = @api.sent.last[1]

    assert_equal "message", final["type"]
    assert_equal "Hello", final["text"]
    assert_equal(
      {
        "type" => "https://schema.org/Message",
        "@type" => "Message",
        "@context" => "https://schema.org",
        "additionalType" => ["AIGeneratedContent"]
      },
      final["entities"].find { |entity| entity["type"] == "https://schema.org/Message" }
    )
  end

  # A card-only stream never sends a chunk, so no stream id is assigned and
  # close sends nothing, matching TypeScript/Python (their close returns
  # early with no content). Card finals belong after text chunks, via
  # clear_text if needed.
  def test_stream_card_only_emit_sends_nothing
    @teams.on_message do |ctx|
      fast_stream(ctx.stream)
      ctx.stream.emit(
        Teams::Api::MessageActivity.new.add_card(
          "type" => "AdaptiveCard",
          "version" => "1.6",
          "body" => [
            { "type" => "TextBlock", "text" => "Card only" }
          ]
        )
      )
      wait_for_stream_idle(ctx.stream)
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_empty @api.sent
    assert_empty @api.updates
  end

  def test_stream_clear_text_discards_accumulated_text_before_card_final
    @teams.on_message do |ctx|
      fast_stream(ctx.stream)
      ctx.stream.emit "discard this"
      wait_until { @api.sent.size == 1 }
      ctx.stream.clear_text
      ctx.stream.emit(
        Teams::Api::MessageActivity.new.add_card(
          "type" => "AdaptiveCard",
          "version" => "1.6",
          "body" => [
            { "type" => "TextBlock", "text" => "Card only" }
          ]
        )
      )
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal 2, @api.sent.size
    assert_equal 0, @api.updates.size

    final = @api.sent.last[1]

    assert_equal "message", final["type"]
    refute final.key?("text")
    assert_equal "application/vnd.microsoft.card.adaptive", final["attachments"].first["contentType"]
    assert_equal "final", final.dig("channelData", "streamType")
  end

  def test_stream_clear_text_allows_later_text
    @teams.on_message do |ctx|
      fast_stream(ctx.stream)
      ctx.stream.emit "discard this"
      wait_until { @api.sent.size == 1 }
      ctx.stream.clear_text
      ctx.stream.emit "keep this"
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal 0, @api.updates.size
    assert_equal "discard this", @api.sent[0][1]["text"]
    assert_equal "keep this", @api.sent[1][1]["text"]
    assert_equal "keep this", @api.sent[2][1]["text"]
  end

  # Chunk-send errors are classified and swallowed on the flusher thread, so
  # the mapping surfaces through close's final send, like TypeScript/Python.
  def test_stream_maps_403_error_messages_to_typed_errors
    {
      "Content stream was canceled by user." => Teams::StreamCancelledError,
      "Content stream is not allowed" => Teams::StreamNotAllowedError,
      "Content stream is not allowed on an already completed streamed message" => Teams::TerminalStreamError,
      "Message size too large" => Teams::TerminalStreamError,
      "Request streamed content should contain the previously streamed content" => Teams::TerminalStreamError
    }.each do |message, expected|
      api = FakeApi.new
      api.send_filter = ->(payload) { raise stream_http_error(message) if payload["type"] == "message" }
      stream = build_stream(api)

      stream.emit "hi"
      error = assert_raises(Teams::Error, "expected a stream error for #{message.inspect}") { stream.close }
      assert_instance_of expected, error, "wrong error class for #{message.inspect}"
      assert_equal message, error.message
    end
  end

  def test_stream_403_with_empty_body_maps_to_terminal_error
    api = FakeApi.new
    api.send_filter = ->(payload) { raise stream_http_error if payload["type"] == "message" }
    stream = build_stream(api)

    stream.emit "hi"
    error = assert_raises(Teams::TerminalStreamError) { stream.close }
    assert_instance_of Teams::TerminalStreamError, error
  end

  def test_stream_not_allowed_does_not_mark_canceled_or_timed_out
    api = FakeApi.new
    api.send_filter = ->(payload) { raise stream_http_error("Content stream is not allowed") if payload["type"] == "message" }
    stream = build_stream(api)

    stream.emit "hi"
    assert_raises(Teams::StreamNotAllowedError) { stream.close }
    refute stream.canceled
    refute stream.timed_out
  end

  def test_stream_cancel_is_sticky_and_close_returns_nil
    api = FakeApi.new
    api.send_filter = ->(_payload) { raise stream_http_error("Content stream was canceled by user.") }
    stream = build_stream(api)

    # The cancelling 403 lands on the flusher thread and is swallowed there;
    # the sticky flag is the observable, like TypeScript/Python.
    stream.emit "hi"
    wait_until { stream.canceled }
    assert_nil stream.close

    api.send_filter = nil
    error = assert_raises(Teams::StreamCancelledError) { stream.emit "again" }
    assert_equal "Stream has been cancelled.", error.message
  end

  def test_stream_chunk_timeout_is_swallowed_and_close_updates_in_place
    api = FakeApi.new
    stream = build_stream(api)

    stream.emit "Hello"
    wait_until { api.sent.size == 1 }
    api.send_filter = ->(_payload) { raise stream_http_error("Content stream finished due to exceeded streaming time.") }
    stream.emit ", world"

    wait_until { stream.timed_out }
    api.send_filter = nil

    result = stream.close

    assert_instance_of Teams::Api::SentActivity, result
    assert_equal "sent-1", result.id
    assert_equal 1, api.sent.size
    assert_equal 1, api.updates.size

    final = api.updates.last[2]
    assert_equal "message", final["type"]
    assert_equal "Hello, world", final["text"]
    assert_equal "sent-1", final["id"]
    refute final.key?("channelData")
    refute Array(final["entities"]).any? { |entity| entity["type"] == "streaminfo" }
  end

  def test_stream_final_send_timeout_falls_back_to_in_place_update
    api = FakeApi.new
    stream = build_stream(api)

    stream.emit "Hello"
    api.send_filter = lambda do |payload|
      raise stream_http_error("Content stream finished due to exceeded streaming time.") if payload["type"] == "message"
    end

    result = stream.close

    assert stream.timed_out
    assert_equal "sent-1", result.id
    assert_equal 1, api.updates.size

    final = api.updates.last[2]
    assert_equal "message", final["type"]
    assert_equal "Hello", final["text"]
    assert_equal "sent-1", final["id"]
    refute final.key?("channelData")
    refute Array(final["entities"]).any? { |entity| entity["type"] == "streaminfo" }
  end

  def test_stream_reusable_after_close_starts_new_streamed_message
    api = FakeApi.new
    stream = build_stream(api)

    stream.emit "one"
    first = stream.close

    assert stream.closed
    assert_same first, stream.close

    stream.emit "two"

    refute stream.closed
    second = stream.close

    assert_equal "sent-1", first.id
    assert_equal "sent-3", second.id
    assert_equal 4, api.sent.size
    assert_equal 0, api.updates.size

    second_chunk = api.sent[2][1]
    refute second_chunk.key?("id")
    refute second_chunk.dig("channelData", "streamId")
    assert_equal 1, second_chunk.dig("channelData", "streamSequence")
    assert_equal "one", api.sent[1][1]["text"]
    assert_equal "two", second_chunk["text"]

    second_final = api.sent[3][1]
    assert_equal "sent-3", second_final["entities"].first["streamId"]
  end

  def test_post_defaults_to_targeted_when_inbound_message_is_targeted
    @teams.on_message { |ctx| ctx.post "Secret message" }

    post "/api/messages", JSON.generate(targeted_teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_empty @api.sent
    assert_equal 1, @api.targeted_sent.size

    outbound = @api.targeted_sent.first[1]
    assert_equal "Secret message", outbound["text"]
    assert_equal "user-1", outbound.dig("recipient", "id")
    assert_equal "User One", outbound.dig("recipient", "name")
    assert_equal true, outbound.dig("recipient", "isTargeted")
    assert_includes outbound["entities"], { "type" => "targetedMessageInfo", "messageId" => "activity-1" }
  end

  def test_reply_defaults_to_targeted_without_quoting
    @teams.on_message { |ctx| ctx.reply "Private reply" }

    post "/api/messages", JSON.generate(targeted_teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_empty @api.sent
    assert_equal 1, @api.targeted_sent.size

    outbound = @api.targeted_sent.first[1]
    assert_equal "Private reply", outbound["text"]
    refute outbound.key?("replyToId")
    assert_equal true, outbound.dig("recipient", "isTargeted")
    refute(Array(outbound["entities"]).any? { |entity| entity["type"] == "quotedReply" })
    assert_includes outbound["entities"], { "type" => "targetedMessageInfo", "messageId" => "activity-1" }
  end

  def test_explicit_recipient_opts_out_of_targeted_defaulting
    @teams.on_message do |ctx|
      ctx.post Teams::Api::MessageActivity.new("Public message").with_recipient({ "id" => "user-1", "name" => "User One" })
    end

    post "/api/messages", JSON.generate(targeted_teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_empty @api.targeted_sent
    assert_equal 1, @api.sent.size

    outbound = @api.sent.first[1]
    assert_equal "user-1", outbound.dig("recipient", "id")
    refute outbound.dig("recipient", "isTargeted")
    refute outbound.key?("entities")
  end

  def test_update_does_not_default_to_targeted
    @teams.on_message { |ctx| ctx.update "assistant-activity-1", "Edited." }

    post "/api/messages", JSON.generate(targeted_teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_empty @api.targeted_sent
    assert_empty @api.targeted_updates
    assert_equal 1, @api.updates.size
  end

  def test_targeted_outbound_strips_quoted_reply_metadata
    @teams.on_message do |ctx|
      ctx.post(
        "type" => "message",
        "text" => %(<quoted messageId="activity-1"/> Secret),
        "entities" => [{ "type" => "quotedReply", "quotedReply" => { "messageId" => "activity-1" } }]
      )
    end

    post "/api/messages", JSON.generate(targeted_teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    outbound = @api.targeted_sent.first[1]
    assert_equal "Secret", outbound["text"]
    refute(outbound["entities"].any? { |entity| entity["type"] == "quotedReply" })
    assert_includes outbound["entities"], { "type" => "targetedMessageInfo", "messageId" => "activity-1" }
  end

  def test_explicit_targeted_send_from_public_inbound_has_no_targeted_message_info
    @teams.on_message do |ctx|
      ctx.post Teams::Api::MessageActivity.new("Targeted send").with_recipient(
        { "id" => "user-1", "name" => "User One" }, is_targeted: true
      )
    end

    payload = teams_payload
    payload["conversation"] = payload["conversation"].merge("conversationType" => "groupChat")
    post "/api/messages", JSON.generate(payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_equal 1, @api.targeted_sent.size

    outbound = @api.targeted_sent.first[1]
    assert_equal true, outbound.dig("recipient", "isTargeted")
    refute(Array(outbound["entities"]).any? { |entity| entity["type"] == "targetedMessageInfo" })
  end

  def test_targeted_update_routes_to_targeted_update
    @teams.on_message do |ctx|
      ctx.post Teams::Api::MessageActivity.new("Updated", id: "existing-1").with_recipient(
        { "id" => "user-1" }, is_targeted: true
      )
    end

    post "/api/messages", JSON.generate(targeted_teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?
    assert_empty @api.updates
    assert_equal 1, @api.targeted_updates.size
    assert_equal "existing-1", @api.targeted_updates.first[1]
  end

  def test_targeted_send_in_personal_chat_raises
    payload = teams_payload
    payload["conversation"] = payload["conversation"].merge("conversationType" => "personal")
    reference = Teams::Api::ConversationReference.from_activity(Teams::Activity.new(payload))

    error = assert_raises(ArgumentError) do
      @teams.send_activity(
        reference,
        Teams::Api::MessageActivity.new("Secret").with_recipient({ "id" => "user-1" }, is_targeted: true)
      )
    end

    assert_equal "Targeted messages are not supported in 1:1 (personal) chats.", error.message
    assert_empty @api.targeted_sent
  end

  def test_stream_chunk_and_close_events
    api = FakeApi.new
    stream = build_stream(api)

    chunks = []
    closes = []
    stream.on_chunk { |sent| chunks << sent }
    stream.on_close { |sent| closes << sent }

    stream.update "Thinking..."
    stream.emit "Hello"
    first = stream.close

    assert_equal 2, chunks.length
    assert(chunks.all? { |sent| sent.is_a?(Teams::Api::SentActivity) })
    assert_equal "sent-1", chunks.first.id
    assert_equal [first], closes

    # Idempotent close does not re-fire the close event.
    stream.close
    assert_equal 1, closes.length

    # Handlers persist across stream reuse.
    stream.emit "second cycle"
    second = stream.close

    assert_equal 3, chunks.length
    assert_equal [first, second], closes
  end

  def test_typing_accepts_optional_text
    @teams.on_message do |ctx|
      ctx.typing
      ctx.typing "Thinking..."
    end

    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }

    assert last_response.ok?

    plain = @api.sent[0][1]
    with_text = @api.sent[1][1]

    assert_equal "typing", plain["type"]
    refute plain.key?("text")
    assert_equal "typing", with_text["type"]
    assert_equal "Thinking...", with_text["text"]
  end

  private

  def build_stream(api)
    teams = Teams::App.new(api:, skip_auth: true, logger: @logger)
    activity = Teams::Activity.new(teams_payload)
    conversation_reference = Teams::Api::ConversationReference.from_activity(activity)
    fast_stream(Teams::HttpStream.new(app: teams, conversation_reference:))
  end

  # Shrinks the stream's flush/poll intervals so tests exercising the
  # background flusher stay fast.
  def fast_stream(stream)
    stream.instance_variable_set(:@flush_interval, 0.01)
    stream.instance_variable_set(:@poll_interval, 0.005)
    stream.instance_variable_set(:@total_wait_timeout, 2)
    stream
  end

  def wait_until(timeout: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      flunk "timed out waiting for condition" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.005
    end
  end

  def wait_for_stream_idle(stream)
    wait_until { stream.count.zero? && !stream.instance_variable_get(:@flushing) }
  end

  def stream_http_error(message = nil)
    body = message ? { "error" => { "message" => message } } : ""
    Teams::HttpError.new("HTTP request failed with status 403", status: 403, headers: {}, body:)
  end
end
