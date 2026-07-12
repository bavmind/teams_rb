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

  def test_accepts_api_audience_form
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload.merge("aud" => "api://client-id"))
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    payload = validator.validate!("Bearer #{token}")

    assert_equal "api://client-id", payload["aud"]
  end

  def test_accepts_botid_audience_form
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload.merge("aud" => "api://botid-client-id"))
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    payload = validator.validate!("Bearer #{token}")

    assert_equal "api://botid-client-id", payload["aud"]
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

  def test_rejects_missing_authorization_header
    _rsa, _kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!(nil) }
    assert_equal "Authorization header is required", error.message

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("") }
    assert_equal "Authorization header is required", error.message
  end

  def test_rejects_non_bearer_scheme
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Basic #{token}") }
    assert_equal "Authorization must be Bearer", error.message
  end

  def test_rejects_malformed_token
    _rsa, _kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer not-a-jwt") }
    assert_equal "JWT must contain three segments", error.message

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer only.two") }
    assert_equal "JWT must contain three segments", error.message

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer @@@.@@@.@@@") }
    assert_equal "JWT is malformed", error.message
  end

  def test_rejects_expired_token
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload.merge("exp" => Time.now.to_i - 60))
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    assert_equal "JWT expired", error.message
  end

  def test_rejects_not_yet_active_token
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload.merge("nbf" => Time.now.to_i + 3600))
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    assert_equal "JWT not active yet", error.message
  end

  def test_rejects_wrong_issuer
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload.merge("iss" => "https://evil.example.com"))
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    assert_equal "JWT issuer is invalid", error.message
  end

  def test_rejects_tenant_issuer_when_no_tenant_configured
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload.merge("iss" => "https://sts.windows.net/tenant-1/"))
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    assert_equal "JWT issuer is invalid", error.message
  end

  def test_rejects_token_signed_with_wrong_key
    _rsa, kid, cloud, http = validator_parts
    other_rsa = OpenSSL::PKey::RSA.generate(2048)
    # Signed by a different key, but claiming the kid of the published JWK.
    token = JwtTestHelper.token(rsa: other_rsa, kid:, payload: valid_payload)
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    assert_equal "JWT signature is invalid", error.message
  end

  def test_rejects_token_with_unknown_signing_key
    rsa, _kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid: "unknown-kid", payload: valid_payload)
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    assert_equal "JWT signing key was not found", error.message
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
      graph_scope: "https://graph.microsoft.com/.default"
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
