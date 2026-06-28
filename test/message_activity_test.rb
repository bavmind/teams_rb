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
end
