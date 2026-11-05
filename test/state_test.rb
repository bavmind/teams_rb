# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class StateTest < Minitest::Test
  include Rack::Test::Methods

  def test_turn_state_behaves_like_a_hash_with_string_keys
    state = Teams::State::TurnState.new("a" => 1)
    state[:b] = 2

    assert_equal 1, state[:a]
    assert_equal 2, state["b"]
    assert state.key?(:b)
    assert_equal %w[a b], state.keys
    assert_equal [["a", 1], ["b", 2]], state.to_a
    assert_equal 2, state.size
    assert_equal 3, state.fetch("c", 3)
    assert_equal 2, state.delete(:b)
    refute state.empty?
    assert state.clear.empty?
  end

  def test_dirty_tracking_follows_content_not_writes
    state = Teams::State::TurnState.new("prefs" => { "theme" => "dark" }, "count" => 1)
    refute state.dirty?

    state["count"]
    refute state.dirty?, "reads do not dirty"

    state["prefs"]["theme"] = "light"
    assert state.dirty?, "nested mutations are detected"

    state["prefs"]["theme"] = "dark"
    refute state.dirty?, "reverted changes are clean"

    state["count"] = 2
    state.mark_clean
    refute state.dirty?
  end

  def test_sealed_state_raises_on_access
    state = Teams::State::TurnState.new("a" => 1).seal

    assert state.sealed?
    assert_raises(Teams::State::TurnStateSealedError) { state["a"] }
    assert_raises(Teams::State::TurnStateSealedError) { state["a"] = 2 }
    assert_raises(Teams::State::TurnStateSealedError) { state.each { nil } }
  end

  def test_loader_percent_encodes_key_segments
    loader = Teams::State::TurnStateLoader.new(storage: Teams::Storage::MemoryStore.new, key_prefix: "app")

    assert_equal "app:conv:a%3Ab%2Fc%20d", loader.conversation_key("a:b/c d")
    assert_equal "app:user:19%3Aabc%40thread.v2:29%3Auser", loader.user_key("19:abc@thread.v2", "29:user")
    refute_equal loader.user_key("a:b", "c"), loader.user_key("a", "b:c")
  end

  def test_loader_loads_json_strings_parsed_hashes_and_discards_malformed_blobs
    storage = Teams::Storage::MemoryStore.new
    loader = Teams::State::TurnStateLoader.new(storage:)
    storage.set(loader.conversation_key("c1"), '{"count":3}')
    storage.set(loader.user_key("c1", "u1"), { "name" => "Ada" })
    storage.set(loader.conversation_key("bad"), "{not json")

    container = loader.load("c1", "u1")
    assert_equal 3, container.conversation["count"]
    assert_equal "Ada", container.user["name"]
    refute container.conversation.dirty?

    broken = loader.load("bad")
    assert broken.conversation.empty?
    assert_nil broken.user
    assert_nil storage.get(loader.conversation_key("bad"))
  end

  def test_save_writes_dirty_scopes_and_deletes_emptied_ones
    storage = Teams::Storage::MemoryStore.new
    loader = Teams::State::TurnStateLoader.new(storage:)
    storage.set(loader.user_key("c1", "u1"), '{"seen":true}')

    container = loader.load("c1", "u1")
    container.conversation["count"] = 1
    container.user.delete("seen")
    container.save

    assert_equal({ "count" => 1 }, JSON.parse(storage.get(loader.conversation_key("c1"))))
    assert_nil storage.get(loader.user_key("c1", "u1"))
    refute container.conversation.dirty?
  end

  def test_save_serializes_every_scope_before_writing
    storage = Teams::Storage::MemoryStore.new
    loader = Teams::State::TurnStateLoader.new(storage:)
    container = loader.load("c1", "u1")
    container.conversation["ok"] = 1
    container.user["bad"] = Object.new

    assert_raises(JSON::GeneratorError) { container.save }
    assert_nil storage.get(loader.conversation_key("c1"))
    assert container.conversation.dirty?
  end

  def test_container_delete_removes_storage_and_clears_scopes
    storage = Teams::Storage::MemoryStore.new
    loader = Teams::State::TurnStateLoader.new(storage:)
    storage.set(loader.conversation_key("c1"), '{"a":1}')
    storage.set(loader.user_key("c1", "u1"), '{"b":2}')

    container = loader.load("c1", "u1")
    container.delete

    assert_nil storage.get(loader.conversation_key("c1"))
    assert_nil storage.get(loader.user_key("c1", "u1"))
    assert container.conversation.empty?
    refute container.user.dirty?
  end

  def test_state_is_nil_unless_enabled
    seen = :unset
    @teams = build_app
    @teams.on_message { |ctx| seen = ctx.state }

    post_message

    assert_nil seen
  end

  def test_state_persists_across_turns_and_is_sealed_after_the_turn
    log = StringIO.new
    @teams = build_app(state: true, logger: Logger.new(log))
    counts = []
    retained = nil
    @teams.on_message do |ctx|
      ctx.state.conversation["count"] = ctx.state.conversation.fetch("count", 0) + 1
      ctx.state.user["name"] ||= ctx.activity.from.id
      counts << ctx.state.conversation["count"]
      retained = ctx.state
    end

    post_message
    post_message

    assert_equal [1, 2], counts
    assert_includes log.string, "in-memory storage"
    assert_equal({ "count" => 2 }, JSON.parse(@teams.storage.get("ts:conv:conversation-1")))
    assert_equal({ "name" => "user-1" }, JSON.parse(@teams.storage.get("ts:user:conversation-1:user-1")))
    assert_raises(Teams::State::TurnStateSealedError) { retained.conversation["count"] }
  end

  def test_state_options_select_storage_and_key_prefix
    storage = Teams::Storage::MemoryStore.new
    @teams = build_app(state: Teams::State::StateOptions.new(storage:, key_prefix: "bot"))
    @teams.on_message { |ctx| ctx.state.conversation["x"] = 1 }

    post_message

    assert_equal '{"x":1}', storage.get("bot:conv:conversation-1")
    assert_nil @teams.storage.get("ts:conv:conversation-1")
  end

  def test_state_is_saved_when_a_handler_raises
    @teams = build_app(state: true)
    @teams.on_message do |ctx|
      ctx.state.conversation["partial"] = true
      raise "boom"
    end

    post_message

    assert_equal 500, last_response.status
    assert_equal '{"partial":true}', @teams.storage.get("ts:conv:conversation-1")
  end

  def test_state_save_failure_is_reported_and_fails_a_successful_turn
    @teams = build_app(state: true)
    errors = []
    @teams.on_error { |error, _activity| errors << error.class }
    @teams.on_message { |ctx| ctx.state.conversation["bad"] = Object.new }

    post_message

    assert_equal 500, last_response.status
    assert_equal [JSON::GeneratorError], errors
  end

  def test_invalid_state_option_is_rejected
    assert_raises(ArgumentError) { build_app(state: { storage: nil }) }
  end

  private

  def app
    @teams.to_rack
  end

  def build_app(**options)
    defaults = { api: FakeApi.new, dangerously_allow_unauthenticated_requests: true, logger: Logger.new(nil) }
    Teams::App.new(**defaults.merge(options))
  end

  def post_message
    post "/api/messages", JSON.generate(teams_payload), { "CONTENT_TYPE" => "application/json" }
  end
end
