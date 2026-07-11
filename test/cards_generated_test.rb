# frozen_string_literal: true

require_relative "test_helper"

# Golden tests: the corpus is produced by script/extract_cards_ir.py from the
# Python SDK's generated card models. Every sample asserts that the Ruby
# generated classes serialize to exactly what Pydantic emits.
class CardsGeneratedTest < Minitest::Test
  CORPUS = JSON.parse(File.read(File.expand_path("fixtures/cards_corpus.json", __dir__)))

  CORPUS.each_with_index do |sample, index|
    class_name = sample.dig("spec", "__class__")
    define_method("test_golden_#{index}_#{class_name.downcase}") do
      built = build_spec(sample["spec"])

      assert_equal sample["expected"], built.to_h
    end
  end

  def test_every_generated_class_instantiates_and_serializes
    generated = Teams::Cards.constants
      .map { |const| Teams::Cards.const_get(const) }
      .select { |const| const.is_a?(Class) && const < Teams::Cards::GeneratedCard }

    assert_operator generated.length, :>=, 112

    generated.each do |klass|
      assert_kind_of Hash, klass.new.to_h, "#{klass.name} failed to serialize"
    end
  end

  def test_mutable_defaults_are_not_shared_between_instances
    first = Teams::Cards::TextBlock.new("a")
    second = Teams::Cards::TextBlock.new("b")
    first.requires["capability"] = "x"

    refute second.requires.key?("capability")
  end

  def test_preserved_ruby_conveniences
    card = Teams::Cards::AdaptiveCard.new(
      Teams::Cards::TextBlock.new("hello"),
      Teams::Cards::ActionSet.new(Teams::Cards::SubmitAction.new(title: "Go"))
    ).add_item(Teams::Cards::TextBlock.new("more"))

    body = card.to_h

    assert_equal "AdaptiveCard", body["type"]
    assert_equal "1.5", body["version"]
    assert_equal %w[TextBlock ActionSet TextBlock], body["body"].map { |item| item["type"] }
    assert_equal "https://example.com", Teams::Cards::OpenUrlAction.new("https://example.com").to_h["url"]
  end

  private

  def build_spec(spec)
    if spec.is_a?(Hash) && spec.key?("__class__")
      klass = Teams::Cards.const_get(spec["__class__"])
      kwargs = (spec["kwargs"] || {}).to_h { |key, value| [key.to_sym, build_spec(value)] }
      klass.new(**kwargs)
    elsif spec.is_a?(Array)
      spec.map { |item| build_spec(item) }
    elsif spec.is_a?(Hash)
      spec.transform_values { |value| build_spec(value) }
    else
      spec
    end
  end
end
