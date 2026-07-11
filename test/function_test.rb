# frozen_string_literal: true

require_relative "test_helper"

class FakeEntraValidator
  def initialize(payload)
    @payload = payload
  end

  def validate!(authorization_header, service_url: nil)
    raise Teams::AuthenticationError, "JWT signature is invalid" unless authorization_header == "Bearer tab-token"

    @payload
  end
end

class FunctionTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @api = FakeApi.new
    @teams = Teams::App.new(api: @api, skip_auth: true, logger: Logger.new(StringIO.new))
    @teams.instance_variable_set(:@jwt_validator, FakeEntraValidator.new(
      "oid" => "00000000-0000-0000-0000-00000000aaaa",
      "tid" => "00000000-0000-0000-0000-0000000000ff",
      "name" => "Test User",
      "appId" => "client-app-id"
    ))
  end

  def app
    @teams.to_rack
  end

  def call_function(name, body: { "message" => "hello" }, headers: {})
    default_headers = {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer tab-token",
      "HTTP_X_TEAMS_APP_SESSION_ID" => "session-1",
      "HTTP_X_TEAMS_PAGE_ID" => "page-1"
    }
    post "/api/functions/#{name}", JSON.generate(body), default_headers.merge(headers)
  end

  def test_unregistered_function_returns_404
    call_function("nope")

    assert_equal 404, last_response.status
    assert_includes JSON.parse(last_response.body)["detail"], "not registered"
  end

  def test_missing_client_headers_return_401_with_detail
    @teams.on_function("echo") { |_ctx| nil }

    call_function("echo", headers: { "HTTP_X_TEAMS_APP_SESSION_ID" => "" })
    assert_equal 401, last_response.status
    assert_includes JSON.parse(last_response.body)["detail"], "X-Teams-App-Session-Id"

    call_function("echo", headers: { "HTTP_X_TEAMS_PAGE_ID" => "" })
    assert_equal 401, last_response.status
    assert_includes JSON.parse(last_response.body)["detail"], "X-Teams-Page-Id"

    call_function("echo", headers: { "HTTP_AUTHORIZATION" => "" })
    assert_equal 401, last_response.status
    assert_includes JSON.parse(last_response.body)["detail"], "Authorization"
  end

  def test_invalid_token_returns_401
    @teams.on_function("echo") { |_ctx| nil }

    call_function("echo", headers: { "HTTP_AUTHORIZATION" => "Bearer wrong" })

    assert_equal 401, last_response.status
    assert_includes JSON.parse(last_response.body)["detail"], "signature"
  end

  def test_missing_token_claim_returns_401
    @teams.instance_variable_set(:@jwt_validator, FakeEntraValidator.new("oid" => "x", "tid" => "y"))
    @teams.on_function("echo") { |_ctx| nil }

    call_function("echo")

    assert_equal 401, last_response.status
    assert_includes JSON.parse(last_response.body)["detail"], "name claim"
  end

  def test_function_receives_context_and_returns_result
    seen = nil
    @teams.on_function("echo") do |ctx|
      seen = ctx
      { "echoed" => ctx.data["message"], "user" => ctx.user_name }
    end

    call_function("echo", headers: { "HTTP_X_TEAMS_CHAT_ID" => "chat-1" })

    assert_equal 200, last_response.status
    assert_equal({ "echoed" => "hello", "user" => "Test User" }, JSON.parse(last_response.body))
    assert_equal "echo", seen.function_name
    assert_equal "00000000-0000-0000-0000-00000000aaaa", seen.user_id
    assert_equal "00000000-0000-0000-0000-0000000000ff", seen.tenant_id
    assert_equal "chat-1", seen.chat_id
    assert_equal "session-1", seen.app_session_id
    assert_equal "tab-token", seen.auth_token
  end

  def test_conversation_resolution_validates_membership
    resolved = nil
    @teams.on_function("where") do |ctx|
      resolved = ctx.conversation_id
      nil
    end

    call_function("where", headers: { "HTTP_X_TEAMS_CHAT_ID" => "chat-1" })
    assert_equal "chat-1", resolved

    @api.member_missing = true
    call_function("where", headers: { "HTTP_X_TEAMS_CHAT_ID" => "chat-1" })
    assert_nil resolved
  end

  def test_personal_scope_creates_conversation_and_posts
    @teams.on_function("notify") do |ctx|
      sent = ctx.post(ctx.data["message"])
      { "conversation" => ctx.conversation_id, "activity" => sent.id }
    end

    call_function("notify", body: { "message" => "Hello from the tab" })

    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal "created-conversation-1", body["conversation"]
    assert_equal 1, @api.created_conversations.length
    assert_equal "00000000-0000-0000-0000-00000000aaaa", @api.created_conversations.first[:members].first["id"]
    assert_equal "created-conversation-1", @api.sent.first[0]
    assert_equal "Hello from the tab", @api.sent.first[1]["text"]
  end

  def test_post_without_resolvable_conversation_raises
    @api.member_missing = true
    error_message = nil
    @teams.on_function("notify") do |ctx|
      begin
        ctx.post("nope")
      rescue Teams::Error => error
        error_message = error.message
      end
      nil
    end

    call_function("notify", headers: { "HTTP_X_TEAMS_CHAT_ID" => "chat-1" })

    assert_includes error_message, "Unable to resolve a conversation"
  end
end
