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
