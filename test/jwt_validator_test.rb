# frozen_string_literal: true

require_relative "test_helper"

class JwtValidatorTest < Minitest::Test
  def test_validates_rs256_token
    rsa, kid, cloud, http = validator_parts
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
    rsa, kid, cloud, http = validator_parts
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

  def test_validates_service_url_claim
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(
      rsa:,
      kid:,
      payload: valid_payload.merge("serviceurl" => "https://smba.trafficmanager.net/teams/")
    )
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    payload = validator.validate!("Bearer #{token}", service_url: "https://smba.trafficmanager.net/teams")

    assert_equal "https://smba.trafficmanager.net/teams/", payload["serviceurl"]
  end

  def test_rejects_service_url_mismatch
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(
      rsa:,
      kid:,
      payload: valid_payload.merge("serviceurl" => "https://smba.trafficmanager.net/teams")
    )
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) do
      validator.validate!("Bearer #{token}", service_url: "https://evil.example.com/teams")
    end

    assert_includes error.message, "Service URL mismatch"
  end

  def test_accepts_aad_v1_issuer_for_configured_tenant
    rsa, kid, cloud, http = validator_parts
    http.responses["https://login.example.com/tenant-1/discovery/v2.0/keys"] = {
      "keys" => [JwtTestHelper.jwk_for(rsa, kid:)]
    }
    token = JwtTestHelper.token(
      rsa:,
      kid:,
      payload: valid_payload.merge("iss" => "https://sts.windows.net/tenant-1/")
    )
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", tenant_id: "tenant-1", cloud:, http:)

    payload = validator.validate!("Bearer #{token}")

    assert_equal "https://sts.windows.net/tenant-1/", payload["iss"]
  end

  private

  def validator_parts
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

    [rsa, kid, cloud, http]
  end

  def valid_payload
    {
      "iss" => "https://api.botframework.com",
      "aud" => "client-id",
      "nbf" => Time.now.to_i - 60,
      "exp" => Time.now.to_i + 3600
    }
  end
end
