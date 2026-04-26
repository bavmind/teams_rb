# frozen_string_literal: true

require_relative "test_helper"

class JwtValidatorTest < Minitest::Test
  def test_validates_rs256_token
    rsa = OpenSSL::PKey::RSA.generate(2048)
    kid = "test-kid"
    cloud = Teams::CloudEnvironment.new(
      login_endpoint: "https://login.example.com",
      login_tenant: "botframework.com",
      bot_scope: "https://api.botframework.com/.default",
      token_service_url: "https://token.botframework.com",
      open_id_metadata_url: "https://login.example.com/.well-known/openidconfiguration",
      token_issuer: "https://api.botframework.com",
      graph_scope: "https://graph.microsoft.com/.default",
      allowed_service_urls: ["smba.trafficmanager.net"]
    )
    http = FakeHttp.new(
      "https://login.example.com/.well-known/openidconfiguration" => { "jwks_uri" => "https://login.example.com/keys" },
      "https://login.example.com/keys" => { "keys" => [JwtTestHelper.jwk_for(rsa, kid:)] }
    )
    token = JwtTestHelper.token(
      rsa:,
      kid:,
      payload: {
        "iss" => "https://api.botframework.com",
        "aud" => "client-id",
        "nbf" => Time.now.to_i - 60,
        "exp" => Time.now.to_i + 3600
      }
    )
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    payload = validator.validate!("Bearer #{token}")

    assert_equal "client-id", payload["aud"]
  end

  def test_rejects_wrong_audience
    rsa = OpenSSL::PKey::RSA.generate(2048)
    kid = "test-kid"
    cloud = Teams::CloudEnvironment.new(
      login_endpoint: "https://login.example.com",
      login_tenant: "botframework.com",
      bot_scope: "https://api.botframework.com/.default",
      token_service_url: "https://token.botframework.com",
      open_id_metadata_url: "https://login.example.com/.well-known/openidconfiguration",
      token_issuer: "https://api.botframework.com",
      graph_scope: "https://graph.microsoft.com/.default",
      allowed_service_urls: ["smba.trafficmanager.net"]
    )
    http = FakeHttp.new(
      "https://login.example.com/.well-known/openidconfiguration" => { "jwks_uri" => "https://login.example.com/keys" },
      "https://login.example.com/keys" => { "keys" => [JwtTestHelper.jwk_for(rsa, kid:)] }
    )
    token = JwtTestHelper.token(
      rsa:,
      kid:,
      payload: {
        "iss" => "https://api.botframework.com",
        "aud" => "other-client-id",
        "nbf" => Time.now.to_i - 60,
        "exp" => Time.now.to_i + 3600
      }
    )
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
  end
end
