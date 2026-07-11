# frozen_string_literal: true

require_relative "test_helper"

class TokenManagerTest < Minitest::Test
  def test_fetches_and_caches_bot_token
    token = unsigned_token(exp: Time.now.to_i + 3600)
    http = FakeHttp.new(
      "https://login.microsoftonline.com/tenant/oauth2/v2.0/token" => { "access_token" => token }
    )
    manager = Teams::Auth::TokenManager.from_env(
      client_id: "client-id",
      client_secret: "secret",
      tenant_id: "tenant",
      http:
    )

    assert_equal token, manager.bot_token
    assert_equal token, manager.bot_token
    assert_equal 1, http.posts.size
    assert_equal "https://login.microsoftonline.com/tenant/oauth2/v2.0/token", http.posts.first[0]
  end

  def test_refreshes_cached_token_expiring_within_skew
    token_url = "https://login.microsoftonline.com/tenant/oauth2/v2.0/token"
    expiring_token = unsigned_token(exp: Time.now.to_i + 30)
    fresh_token = unsigned_token(exp: Time.now.to_i + 3600)
    http = FakeHttp.new(token_url => { "access_token" => expiring_token })
    manager = Teams::Auth::TokenManager.from_env(
      client_id: "client-id",
      client_secret: "secret",
      tenant_id: "tenant",
      http:
    )

    assert_equal expiring_token, manager.bot_token

    # Within the 60-second expiry skew, the cached token must not be reused.
    http.responses[token_url] = { "access_token" => fresh_token }

    assert_equal fresh_token, manager.bot_token
    assert_equal fresh_token, manager.bot_token
    assert_equal 2, http.posts.size
  end

  def test_token_endpoint_failure_propagates_and_is_not_cached
    token_url = "https://login.microsoftonline.com/tenant/oauth2/v2.0/token"
    token = unsigned_token(exp: Time.now.to_i + 3600)
    http = FakeHttp.new(
      token_url => Teams::HttpError.new(
        "Teams API request failed",
        status: 500,
        headers: {},
        body: "server error"
      )
    )
    manager = Teams::Auth::TokenManager.from_env(
      client_id: "client-id",
      client_secret: "secret",
      tenant_id: "tenant",
      http:
    )

    assert_raises(Teams::HttpError) { manager.bot_token }

    http.responses[token_url] = { "access_token" => token }

    assert_equal token, manager.bot_token
    assert_equal 2, http.posts.size
  end

  def test_requires_credentials
    manager = Teams::Auth::TokenManager.from_env(client_id: nil, client_secret: nil, tenant_id: nil)

    assert_raises(Teams::ConfigurationError) { manager.bot_token }
  end

  private

  def unsigned_token(exp:)
    JwtTestHelper.b64(JSON.generate({ "alg" => "none" })) +
      "." +
      JwtTestHelper.b64(JSON.generate({ "exp" => exp })) +
      "."
  end
end
