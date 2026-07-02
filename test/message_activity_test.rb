# frozen_string_literal: true

require_relative "test_helper"

class MessageActivityTest < Minitest::Test
  def test_serializes_text_format
    activity = Teams::Api::MessageActivity.new("line 1<br>line 2", text_format: "xml")

    assert_equal(
      { "type" => "message", "text" => "line 1<br>line 2", "textFormat" => "xml" },
      activity.to_h
    )
  end

  def test_supports_sdk_text_formats
    %w[plain markdown xml extendedmarkdown].each do |format|
      activity = Teams::Api::MessageActivity.new("hello", text_format: format)

      assert_equal format, activity.to_h["textFormat"]
    end
  end

  def test_supports_builder_style_text_format
    activity = Teams::Api::MessageActivity.new("**hello**").with_text_format("markdown")

    assert_equal "markdown", activity.to_h["textFormat"]
  end

  def test_rejects_unknown_text_format
    assert_raises(ArgumentError) do
      Teams::Api::MessageActivity.new("hello", text_format: "html")
    end
  end

  def test_add_ai_generated_adds_root_level_message_entity
    activity = Teams::Api::MessageActivity.new("Hello!").add_ai_generated

    assert_equal(
      [
        {
          "type" => "https://schema.org/Message",
          "@type" => "Message",
          "@context" => "https://schema.org",
          "additionalType" => ["AIGeneratedContent"]
        }
      ],
      activity.to_h["entities"]
    )
  end

  def test_add_ai_generated_is_idempotent
    activity = Teams::Api::MessageActivity.new("Hello!")
      .add_ai_generated
      .add_ai_generated

    assert_equal ["AIGeneratedContent"], activity.to_h["entities"].first["additionalType"]
  end

  def test_add_citation_adds_root_level_message_entity
    activity = Teams::Api::MessageActivity.new("Answer [1]")
      .add_citation(
        1,
        Teams::Api::CitationAppearance.new(
          name: "Source A",
          abstract: "Source excerpt",
          url: "https://example.com/source-a",
          text: "{\"type\":\"AdaptiveCard\"}",
          icon: "PDF",
          keywords: ["policy"]
        )
      )

    assert_equal(
      [
        {
          "type" => "https://schema.org/Message",
          "@type" => "Message",
          "@context" => "https://schema.org",
          "citation" => [
            {
              "@type" => "Claim",
              "position" => 1,
              "appearance" => {
                "@type" => "DigitalDocument",
                "name" => "Source A",
                "abstract" => "Source excerpt",
                "text" => "{\"type\":\"AdaptiveCard\"}",
                "url" => "https://example.com/source-a",
                "encodingFormat" => "application/vnd.microsoft.card.adaptive",
                "image" => { "@type" => "ImageObject", "name" => "PDF" },
                "keywords" => ["policy"]
              }
            }
          ]
        }
      ],
      activity.to_h["entities"]
    )
  end

  def test_add_citation_accepts_hash_appearance
    activity = Teams::Api::MessageActivity.new("Answer [1]")
      .add_citation(1, { name: "Source A", abstract: "Source excerpt" })

    appearance = activity.to_h["entities"].first["citation"].first["appearance"]

    assert_equal "Source A", appearance["name"]
    assert_equal "Source excerpt", appearance["abstract"]
    refute appearance.key?("encodingFormat")
  end

  def test_add_citation_accepts_string_key_hash_appearance
    activity = Teams::Api::MessageActivity.new("Answer [1]")
      .add_citation(1, { "name" => "Source A", "abstract" => "Source excerpt" })

    appearance = activity.to_h["entities"].first["citation"].first["appearance"]

    assert_equal "Source A", appearance["name"]
    assert_equal "Source excerpt", appearance["abstract"]
  end

  def test_add_citation_omits_encoding_format_for_empty_text
    activity = Teams::Api::MessageActivity.new("Answer [1]")
      .add_citation(1, { name: "Source A", abstract: "Source excerpt", text: "" })

    appearance = activity.to_h["entities"].first["citation"].first["appearance"]

    assert_equal "", appearance["text"]
    refute appearance.key?("encodingFormat")
  end

  def test_add_citation_accumulates_on_single_message_entity
    activity = Teams::Api::MessageActivity.new("Answer [1] [2]")
      .add_citation(1, { name: "Source A", abstract: "First" })
      .add_citation(2, { name: "Source B", abstract: "Second" })

    entities = activity.to_h["entities"]

    assert_equal 1, entities.length
    assert_equal [1, 2], entities.first["citation"].map { |citation| citation["position"] }
  end

  def test_add_citation_preserves_ai_generated_label
    activity = Teams::Api::MessageActivity.new("Answer [1]")
      .add_ai_generated
      .add_citation(1, { name: "Source A", abstract: "Source excerpt" })

    entity = activity.to_h["entities"].first

    assert_equal ["AIGeneratedContent"], entity["additionalType"]
    assert_equal 1, entity["citation"].length
  end

  def test_add_feedback_enables_default_feedback_loop
    activity = Teams::Api::MessageActivity.new("Answer").add_feedback

    assert_equal(
      { "feedbackLoop" => { "type" => "default" } },
      activity.to_h["channelData"]
    )
  end

  def test_add_feedback_supports_custom_feedback_loop
    activity = Teams::Api::MessageActivity.new("Answer").add_feedback("custom")

    assert_equal(
      { "feedbackLoop" => { "type" => "custom" } },
      activity.to_h["channelData"]
    )
  end

  def test_add_feedback_rejects_unknown_mode
    assert_raises(ArgumentError) do
      Teams::Api::MessageActivity.new("Answer").add_feedback("sideways")
    end
  end

  def test_add_feedback_is_chainable
    activity = Teams::Api::MessageActivity.new("Answer")
      .add_ai_generated
      .add_feedback

    assert_equal ["AIGeneratedContent"], activity.to_h["entities"].first["additionalType"]
    assert_equal "default", activity.to_h.dig("channelData", "feedbackLoop", "type")
  end

  def test_add_quote_adds_entity_and_placeholder
    activity = Teams::Api::MessageActivity.new.add_quote("msg-1")

    assert_equal %(<quoted messageId="msg-1"/>), activity.to_h["text"]
    assert_equal(
      [{ "type" => "quotedReply", "quotedReply" => { "messageId" => "msg-1" } }],
      activity.to_h["entities"]
    )
  end

  def test_add_quote_appends_response_text
    activity = Teams::Api::MessageActivity.new.add_quote("msg-1", "my response")

    assert_equal %(<quoted messageId="msg-1"/> my response), activity.to_h["text"]
  end

  def test_add_quote_supports_multiple_quotes
    activity = Teams::Api::MessageActivity.new
      .add_quote("msg-1", "response to first")
      .add_quote("msg-2", "response to second")

    assert_equal(
      %(<quoted messageId="msg-1"/> response to first<quoted messageId="msg-2"/> response to second),
      activity.to_h["text"]
    )
    assert_equal 2, activity.get_quoted_messages.length
  end

  def test_prepend_quote
    activity = Teams::Api::MessageActivity.new("reply text").prepend_quote("msg-1")

    assert_equal %(<quoted messageId="msg-1"/> reply text), activity.to_h["text"]
  end

  def test_get_quoted_messages_filters_entities
    activity = Teams::Api::MessageActivity.new
      .add_ai_generated
      .add_quote("msg-1")

    quotes = activity.get_quoted_messages

    assert_equal 1, quotes.length
    assert_equal "msg-1", quotes.first.quoted_reply.message_id
  end

  def test_add_ai_generated_after_quote
    activity = Teams::Api::MessageActivity.new
      .add_quote("msg-1")
      .add_ai_generated

    assert_equal ["quotedReply", "https://schema.org/Message"], activity.to_h["entities"].map { |entity| entity["type"] }
  end
end

class QuotedReplyEntityTest < Minitest::Test
  def test_serializes_full_quoted_reply_entity
    entity = Teams::Api::QuotedReplyEntity.new(
      "quotedReply" => {
        "messageId" => "1234567890",
        "senderId" => "user-1",
        "senderName" => "Test User",
        "preview" => "Hello, world!",
        "time" => "1772050244572",
        "isReplyDeleted" => false,
        "validatedMessageReference" => true
      }
    )

    assert_equal(
      {
        "type" => "quotedReply",
        "quotedReply" => {
          "messageId" => "1234567890",
          "senderId" => "user-1",
          "senderName" => "Test User",
          "preview" => "Hello, world!",
          "time" => "1772050244572",
          "isReplyDeleted" => false,
          "validatedMessageReference" => true
        }
      },
      entity.to_h
    )
  end
end
