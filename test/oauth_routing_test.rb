# frozen_string_literal: true

require_relative "test_helper"

class OAuthRoutingTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @api = FakeApi.new
    @teams = build_app(@api)
  end

  def app
    @teams.to_rack
  end

  def test_token_exchange_routes_to_the_registered_flow
    github = @teams.add_oauth_flow("github")
    flow_events = []
    app_events = []
    github.on_sign_in { |event| flow_events << [event.connection_name, event.token_response.token] }
    @teams.on_sign_in { |_ctx, token| app_events << token.token }
    @api.users.token = "gh-token"

    post_json(exchange_payload("GitHub"))

    assert last_response.ok?
    assert_equal [["github", "gh-token"]], flow_events
    assert_equal ["gh-token"], app_events
  end

  def test_terminal_exchange_errors_notify_the_flow_failure_handlers
    github = @teams.add_oauth_flow("github")
    failures = []
    github.on_sign_in_failure { |event| failures << [event.connection_name, event.code] }
    @api.users.define_singleton_method(:exchange_token) do |**|
      raise Teams::HttpError.new("boom", status: 500, headers: {}, body: "")
    end

    post_json(exchange_payload("github"))

    assert_equal 500, last_response.status
    assert_equal [["github", "tokenservice.http_500"]], failures
  end

  def test_verify_state_probes_the_pending_flow_first
    github = @teams.add_oauth_flow("github")
    @teams.add_oauth_flow("graph")
    completed = []
    github.on_sign_in { |event| completed << event.connection_name }
    @teams.on_message { |ctx| github.sign_in(ctx) }
    post_json(teams_payload)
    accept_codes_for(@api, "github")

    post_json(message_ext_payload("signin/verifyState", "state" => "123456"))

    assert last_response.ok?
    assert_equal ["github"], completed
    probed = @api.users.token_requests.select { |request| request[:code] }.map { |request| request[:connection_name] }
    assert_equal ["github"], probed
    pending = JSON.parse(@teams.storage.get("ts:user:conversation-1:user-1") || "{}").keys.grep(/__oauth:pending/)
    assert_empty pending
  end

  def test_verify_state_falls_through_registered_flows_then_default_and_answers_404
    @teams.add_oauth_flow("github")
    accept_codes_for(@api, nil)

    post_json(message_ext_payload("signin/verifyState", "state" => "123456"))

    assert_equal 404, last_response.status
    assert_equal %w[github graph], @api.users.token_requests.map { |request| request[:connection_name] }
  end

  def test_sign_in_failure_is_attributed_to_the_pending_sso_flow
    github = @teams.add_oauth_flow("github")
    graph = @teams.add_oauth_flow("graph")
    calls = []
    github.on_sign_in_failure { |event| calls << [:github, event.connection_name] }
    graph.on_sign_in_failure { |event| calls << [:graph, event.connection_name] }
    app_events = []
    @teams.on_oauth_sign_in_failure { |event| app_events << event.connection_name }
    @teams.on_message { |ctx| github.sign_in(ctx) }
    post_json(teams_payload)

    post_json(failure_payload)

    assert_equal [[:github, "github"]], calls
    assert_equal ["github"], app_events
  end

  def test_unattributed_failure_notifies_every_flow_with_its_own_name
    github = @teams.add_oauth_flow("github")
    graph = @teams.add_oauth_flow("graph")
    calls = []
    github.on_sign_in_failure { |event| calls << event.connection_name }
    graph.on_sign_in_failure { |event| calls << event.connection_name }
    app_events = []
    @teams.on_oauth_sign_in_failure { |event| app_events << event.connection_name }

    post_json(failure_payload)

    assert_equal %w[github graph], calls
    assert_equal [nil], app_events
  end

  def test_pending_sign_ins_use_the_process_local_cache_without_state
    @teams = build_app(@api, state: false)
    github = @teams.add_oauth_flow("github")
    calls = []
    github.on_sign_in_failure { |event| calls << event.connection_name }
    @teams.add_oauth_flow("graph").on_sign_in_failure { |event| calls << event.connection_name }
    @teams.on_message { |ctx| github.sign_in(ctx) }
    post_json(teams_payload)

    post_json(failure_payload)

    assert_equal ["github"], calls
  end

  def test_completed_exchange_marker_deduplicates_across_instances
    shared = Teams::Storage::MemoryStore.new
    first = build_app(@api, state: Teams::State::StateOptions.new(storage: shared))
    second_api = FakeApi.new
    second = build_app(second_api, state: Teams::State::StateOptions.new(storage: shared))
    signed_in = []
    second.on_sign_in { |_ctx, _token| signed_in << :second }
    @api.users.token = "token"
    second_api.users.token = "token"

    @teams = first
    post_json(exchange_payload("graph"))
    @teams = second
    post_json(exchange_payload("graph"))

    assert last_response.ok?
    assert_empty second_api.users.exchanges
    assert_empty signed_in
  end

  def test_in_flight_duplicate_mirrors_a_raising_owner_as_412
    started = Queue.new
    release = Queue.new
    @api.users.define_singleton_method(:exchange_token) do |**|
      started << true
      release.pop
      raise "network down"
    end
    handlers = @teams.instance_variable_get(:@oauth_handlers)

    owner = Thread.new do
      handlers.token_exchange(invoke_context(exchange_payload("graph")), -> {})
    rescue RuntimeError => error
      error
    end
    started.pop
    waiter = Thread.new { handlers.token_exchange(invoke_context(exchange_payload("graph")), -> {}) }
    Thread.pass until waiter.status == "sleep"
    release << true

    assert_equal "network down", owner.value.message
    response = waiter.value
    assert_equal 412, response.status
    assert_equal "network down", response.body["failureDetail"]
  end

  def test_pending_markers_expire_and_keep_sso_prefixed_names_distinct
    user = Teams::State::TurnState.new
    state = Struct.new(:user).new(user)
    scope = { conversation_id: "c", user_id: "u" }
    Teams::OAuth::PendingSignIns.record(state, nil, "sso:raw", sso_offered: false, **scope)
    Teams::OAuth::PendingSignIns.record(state, nil, "github", sso_offered: true, **scope)
    user["__oauth:pending:stale"] = Teams::OAuth::Timestamps.format(Time.now.to_f - 600)

    pending = Teams::OAuth::PendingSignIns.list(state, nil, **scope)

    assert_equal({ "github" => true, "sso:raw" => false }, pending.to_h { |hint| [hint.connection_name, hint.sso_offered] })
    refute user.key?("__oauth:pending:stale")
  end

  private

  def build_app(api, **options)
    Teams::App.new(api:, dangerously_allow_unauthenticated_requests: true, logger: Logger.new(nil), **options)
  end

  def post_json(payload)
    post "/api/messages", JSON.generate(payload), { "CONTENT_TYPE" => "application/json" }
  end

  def exchange_payload(connection_name)
    message_ext_payload("signin/tokenExchange", "id" => "exchange-1", "connectionName" => connection_name, "token" => "sso")
  end

  def failure_payload
    message_ext_payload("signin/failure", "code" => "resourcematchfailed", "message" => "URI mismatch")
  end

  # Makes the fake Token Service accept a verify-state code only for the
  # given connection (nil: for none).
  def accept_codes_for(api, connection)
    users = api.users
    users.define_singleton_method(:get_token) do |user_id:, connection_name:, channel_id: nil, code: nil|
      token_requests << { user_id:, connection_name:, channel_id:, code: }
      if code.nil? || connection_name != connection
        raise Teams::HttpError.new("not found", status: 404, headers: {}, body: "")
      end

      Teams::Api::TokenResponse.new("connectionName" => connection_name, "token" => "#{connection_name}-token")
    end
  end

  def invoke_context(payload)
    activity = Teams::Activity.new(payload)
    Teams::ActivityContext.new(
      app: @teams, activity:, conversation_reference: Teams::Api::ConversationReference.from_activity(activity)
    )
  end
end
