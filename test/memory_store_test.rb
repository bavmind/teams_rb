# frozen_string_literal: true

require_relative "test_helper"

class MemoryStoreTest < Minitest::Test
  def test_get_set_delete
    store = Teams::Storage::MemoryStore.new("seed" => 1)

    assert_equal 1, store.get("seed")
    store.set("key", "value")
    assert_equal "value", store.get("key")
    store.delete("key")
    assert_nil store.get("key")
  end

  def test_concurrent_writes_are_all_stored
    store = Teams::Storage::MemoryStore.new

    Array.new(8) do |thread_index|
      Thread.new do
        25.times { |i| store.set("t#{thread_index}-#{i}", thread_index) }
      end
    end.each(&:join)

    8.times do |thread_index|
      25.times { |i| assert_equal thread_index, store.get("t#{thread_index}-#{i}") }
    end
  end
end
