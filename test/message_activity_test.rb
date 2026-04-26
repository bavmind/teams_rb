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

  def test_supports_plain_markdown_and_xml
    %w[plain markdown xml].each do |format|
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
end
