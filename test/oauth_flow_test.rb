# frozen_string_literal: true

require_relative "test_helper"

class OAuthFlowTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @api = FakeApi.new
    @teams = Teams::App.new(api: @api, dangerously_allow_unauthenticated_requests: true, logger: Logger.new(nil))
  end

  def app
    @teams.to_rack
  end

  def test_flows_register_and_resolve_case_insensitively
    github = @teams.add_oauth_flow(" GitHub ", oauth_card_text: "Sign in with GitHub")

    assert_equal "GitHub", github.connection_name
    assert_same github, @teams.get_oauth_flow("github")
    assert_raises(ArgumentError) { @teams.add_oauth_flow("GITHUB") }
    assert_raises(ArgumentError) { @teams.add_oauth_flow("  ") }
    error = assert_raises(ArgumentError) { @teams.get_oauth_flow("graph") }
    assert_includes error.message, "Registered connections: GitHub."
  end

  def test_registering_a_flow_enables_state_unless_the_app_chose
    @teams.add_oauth_flow("graph")
    seen = nil
    @teams.on_message { |ctx| seen = ctx.state }
    post_json(teams_payload)
    assert_instance_of Teams::State::TurnStateContainer, seen

    opted_out = Teams::App.new(api: FakeApi.new, dangerously_allow_unauthenticated_requests: true,
      logger: Logger.new(nil), state: false)
    opted_out.add_oauth_flow("graph")
    assert_nil opted_out.instance_variable_get(:@state_loader)
  end

  def test_flow_sign_in_sends_the_card_on_its_own_connection
    flow = @teams.add_oauth_flow("github", oauth_card_text: "Sign in with GitHub", sign_in_button_text: "Continue")
    @teams.on_message { |ctx| flow.sign_in(ctx) }

    post_json(teams_payload)

    card = @api.sent.first[1]["attachments"].first["content"]
    assert_equal "github", card["connectionName"]
    assert_equal "Sign in with GitHub", card["text"]
    assert_equal "Continue", card.dig("buttons", 0, "title")
    assert_equal "github", @api.users.token_requests.first[:connection_name]
  end

  def test_flow_token_helpers_and_sign_out_use_the_flow_connection
    flow = @teams.add_oauth_flow("github")
    results = {}
    @teams.on_message do |ctx|
      results[:missing] = flow.get_token(ctx)
      @api.users.token = "gh-token"
      results[:token] = flow.get_token(ctx)
      results[:signed_in] = flow.signed_in?(ctx)
      flow.sign_out(ctx)
    end

    post_json(teams_payload)

    assert_nil results[:missing]
    assert_equal "gh-token", results[:token]
    assert results[:signed_in]
    assert_equal "github", @api.users.sign_outs.first[:connection_name]
  end

  def test_get_user_token_only_treats_404_as_signed_out
    @api.users.define_singleton_method(:get_token) do |**|
      raise Teams::HttpError.new("unavailable", status: 503, headers: {}, body: "")
    end
    errors = []
    @teams.on_message do |ctx|
      ctx.get_user_token
    rescue Teams::HttpError => error
      errors << error.status
    end

    post_json(teams_payload)

    assert_equal [503], errors
  end

  def test_sign_in_raises_on_non_404_token_service_failures
    @api.users.define_singleton_method(:get_token) do |**|
      raise Teams::HttpError.new("bad request", status: 400, headers: {}, body: "")
    end
    @teams.on_message { |ctx| ctx.sign_in }

    post_json(teams_payload)

    assert_equal 500, last_response.status
    assert_empty @api.sent
  end

  def test_connection_status_rechecks_registered_flows
    @teams.add_oauth_flow("graph")
    @teams.add_oauth_flow("github")
    @api.users.define_singleton_method(:get_token_status) do |**|
      [
        Teams::Api::TokenStatus.new("connectionName" => "Graph", "hasToken" => false),
        Teams::Api::TokenStatus.new("connectionName" => "other", "hasToken" => false)
      ]
    end
    @api.users.token = "fresh"
    statuses = nil
    @teams.on_message { |ctx| statuses = ctx.get_connection_status }

    post_json(teams_payload)

    assert_equal [["Graph", true], ["other", false], ["github", true]],
      statuses.map { |status| [status.connection_name, status.has_token] }
  end

  def test_signin_failure_emits_a_structured_event
    events = []
    @teams.on_oauth_sign_in_failure { |event| events << event }

    post_json(message_ext_payload("signin/failure", "code" => "resourcematchfailed", "message" => "URI mismatch"))

    assert_equal 1, events.length
    assert_equal ["graph", "resourcematchfailed", "URI mismatch"],
      [events.first.connection_name, events.first.code, events.first.message]
  end

  def test_flow_handlers_are_isolated_from_each_other
    flow = Teams::OAuth::Flow.new("graph", logger: Logger.new(nil))
    calls = []
    flow.on_sign_in { raise "broken listener" }
    flow.on_sign_in { |event| calls << event.connection_name }

    flow.invoke_sign_in_handlers(Teams::OAuth::SignInEvent.new(connection_name: "graph"))

    assert_equal ["graph"], calls
    assert flow.sign_in_handlers?
    refute flow.sign_in_failure_handlers?
  end

  private

  def post_json(payload)
    post "/api/messages", JSON.generate(payload), { "CONTENT_TYPE" => "application/json" }
  end
end
