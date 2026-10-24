# frozen_string_literal: true

require_relative "test_helper"
require "webmock/minitest"

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
    assert_includes error.message, "JWT validation failed"

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer only.two") }
    assert_includes error.message, "JWT validation failed"

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer @@@.@@@.@@@") }
    assert_includes error.message, "JWT validation failed"
  end

  def test_rejects_expired_token
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload.merge("exp" => Time.now.to_i - 300))
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    assert_includes error.message, "expired"
  end

  def test_rejects_not_yet_active_token
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload.merge("nbf" => Time.now.to_i + 360))
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    assert_includes error.message, "nbf"
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
    assert_includes error.message, "Signature verification failed"
  end

  def test_rejects_token_with_unknown_signing_key
    rsa, _kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid: "unknown-kid", payload: valid_payload)
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    assert_includes error.message, "Could not find public key"
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

  def test_accepts_expiry_and_not_before_within_five_minute_clock_tolerance
    rsa, kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    [{ "exp" => Time.now.to_i - 240 }, { "nbf" => Time.now.to_i + 300 }].each do |claims|
      token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload.merge(claims))
      assert_equal "client-id", validator.validate!("Bearer #{token}")["aud"]
    end
  end

  def test_rejects_unsigned_and_non_rs256_tokens_before_fetching_keys
    rsa, kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    tokens = [
      JWT.encode(valid_payload, nil, "none"),
      JWT.encode(valid_payload, rsa.public_key.to_pem, "HS256", { kid: })
    ]

    tokens.each do |token|
      assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    end
    assert_empty http.gets
  end

  def test_rejects_malformed_token_shapes_and_key_ids
    rsa, kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    tokens = [
      "#{JwtTestHelper.token(rsa:, kid:, payload: valid_payload)}.extra",
      JwtTestHelper.token(rsa:, kid:, payload: []),
      JwtTestHelper.token(rsa:, kid: [], payload: valid_payload)
    ]

    tokens.each do |token|
      assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    end
    assert_empty http.gets
  end

  def test_accepts_missing_kid_only_when_one_signing_key_is_available
    rsa, _kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid: nil, payload: valid_payload)
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    assert_equal "client-id", validator.validate!("Bearer #{token}")["aud"]

    http.responses[keys_uri]["keys"] << JwtTestHelper.jwk_for(rsa, kid: "second")
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
  end

  def test_refreshes_rotated_keys_at_ten_minute_expiry_before_the_default_grace
    rsa, kid, cloud, http = validator_parts
    rotated_rsa = OpenSSL::PKey::RSA.generate(2048)
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    validator.validate!("Bearer #{token}")

    http.responses[keys_uri] = { "keys" => [JwtTestHelper.jwk_for(rsa, kid:), JwtTestHelper.jwk_for(rotated_rsa, kid: "rotated")] }
    rotated = JwtTestHelper.token(rsa: rotated_rsa, kid: "rotated", payload: valid_payload)

    assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{rotated}") }
    assert_equal 1, http.gets.count(keys_uri)
    age_cached_keys(validator, seconds: 600)
    assert_equal "client-id", validator.validate!("Bearer #{rotated}")["aud"]
    assert_equal "client-id", validator.validate!("Bearer #{token}")["aud"]
    assert_equal 2, http.gets.count(keys_uri)

    forged = JwtTestHelper.token(rsa:, kid: "rotated", payload: valid_payload)
    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{forged}") }
    assert_includes error.message, "Signature verification failed"
  end

  def test_caches_the_entire_document_including_other_signing_keys
    rsa, kid, cloud, http = validator_parts
    http.responses[keys_uri]["keys"] << JwtTestHelper.jwk_for(rsa, kid: "second")
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    first = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    second = JwtTestHelper.token(rsa:, kid: "second", payload: valid_payload)

    validator.validate!("Bearer #{first}")
    validator.validate!("Bearer #{second}")
    validator.validate!("Bearer #{second}")

    assert_equal 1, http.gets.count(keys_uri)
  end

  def test_missing_keys_do_not_refresh_again_until_cache_expiry
    rsa, _kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    unknown = JwtTestHelper.token(rsa:, kid: "unknown", payload: valid_payload)

    12.times do
      assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{unknown}") }
    end
    assert_equal 1, http.gets.count(keys_uri)

    http.responses[keys_uri]["keys"] << JwtTestHelper.jwk_for(rsa, kid: "unknown")
    age_cached_keys(validator, seconds: 600)
    assert_equal "client-id", validator.validate!("Bearer #{unknown}")["aud"]
    assert_equal 2, http.gets.count(keys_uri)
  end

  def test_known_keys_expire_without_an_unknown_key_triggering_refresh
    rsa, kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    validator.validate!("Bearer #{token}")

    http.responses[keys_uri] = { "keys" => [] }
    age_cached_keys(validator, seconds: 599)
    validator.validate!("Bearer #{token}")
    assert_equal 1, http.gets.count(keys_uri)

    age_cached_keys(validator, seconds: 600)
    assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    unknown = JwtTestHelper.token(rsa:, kid: "unknown", payload: valid_payload)
    assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{unknown}") }
    assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    assert_equal 2, http.gets.count(keys_uri)
  end

  def test_caches_more_than_five_keys_and_keeps_endpoints_independent
    rsa, _kid, cloud, http = validator_parts
    http.responses[keys_uri] = { "keys" => 6.times.map { |i| JwtTestHelper.jwk_for(rsa, kid: "key-#{i}") } }
    tenant_uri = "#{cloud.login_endpoint}/tenant-1/discovery/v2.0/keys"
    http.responses[tenant_uri] = http.responses[keys_uri]
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", tenant_id: "tenant-1", cloud:, http:)
    tokens = 6.times.map { |i| JwtTestHelper.token(rsa:, kid: "key-#{i}", payload: valid_payload) }
    tenant_token = JwtTestHelper.token(rsa:, kid: "key-0", payload: valid_payload.merge("iss" => "https://sts.windows.net/tenant-1/"))

    validator.validate!("Bearer #{tenant_token}")
    tokens.first(5).each { |token| validator.validate!("Bearer #{token}") }
    validator.validate!("Bearer #{tokens[0]}")
    validator.validate!("Bearer #{tokens[5]}")
    validator.validate!("Bearer #{tokens[0]}")
    assert_equal 1, http.gets.count(keys_uri)

    validator.validate!("Bearer #{tokens[1]}")
    assert_equal 1, http.gets.count(keys_uri)
    validator.validate!("Bearer #{tenant_token}")
    assert_equal 1, http.gets.count(tenant_uri)
  end

  def test_failed_expired_key_refresh_preserves_the_set_but_rejects_it_and_can_retry
    rsa, kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    validator.validate!("Bearer #{token}")
    age_cached_keys(validator, seconds: 600)
    provider = validator.instance_variable_get(:@jwks_loaders).fetch(keys_uri)
    previous = provider.cache.fetch(keys_uri)
    http.responses[keys_uri] = Net::ReadTimeout.new("JWKS unavailable")
    missing = JwtTestHelper.token(rsa:, kid: "missing", payload: valid_payload)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{missing}") }
    assert_includes error.message, "JWKS unavailable"
    assert_equal previous, provider.cache.fetch(keys_uri)
    assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    http.responses[keys_uri] = { "keys" => [JwtTestHelper.jwk_for(rsa, kid:)] }
    assert_equal "client-id", validator.validate!("Bearer #{token}")["aud"]
    assert_equal 4, http.gets.count(keys_uri)
  end

  def test_rejects_malformed_key_responses_and_network_failures
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    [nil, "not JSON", { "keys" => {} }, { "keys" => [{ "kid" => kid, "kty" => "RSA" }] }, Net::ReadTimeout.new("timed out")].each do |response|
      validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
      http.responses[keys_uri] = response
      assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    end

    http.responses[keys_uri] = { "keys" => [JwtTestHelper.jwk_for(rsa, kid:)] }
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    assert_equal "client-id", validator.validate!("Bearer #{token}")["aud"]
    assert_equal 6, http.gets.count(keys_uri)
  end

  def test_metadata_failures_reject_authentication_and_can_recover_immediately
    rsa, kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    [Teams::HttpError.new("discovery unavailable", status: 503, headers: {}, body: ""), nil, { "jwks_uri" => "" }].each do |response|
      http.responses[cloud.open_id_metadata_url] = response
      assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    end

    http.responses[cloud.open_id_metadata_url] = { "jwks_uri" => keys_uri }
    assert_equal "client-id", validator.validate!("Bearer #{token}")["aud"]
  end

  def test_http_errors_are_not_cached_and_can_recover_immediately
    rsa, kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    stub_request(:get, keys_uri).to_return(
      { status: 503, body: JSON.generate("keys" => [JwtTestHelper.jwk_for(rsa, kid:)]) },
      { status: 200, body: JSON.generate("keys" => [JwtTestHelper.jwk_for(rsa, kid:)]) }
    )

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    assert_includes error.message, "503"
    assert_requested(:get, keys_uri, times: 1)

    assert_equal "client-id", validator.validate!("Bearer #{token}")["aud"]
    assert_requested(:get, keys_uri, times: 2)
  end

  def test_concurrent_requests_share_a_successful_key_fetch
    rsa, kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    start = Queue.new
    threads = 8.times.map do
      Thread.new do
        start.pop
        validator.validate!("Bearer #{token}")
      end
    end
    8.times { start << true }

    assert_equal ["client-id"] * 8, threads.map { |thread| thread.value["aud"] }
    assert_equal 1, http.gets.count(keys_uri)
  end

  def test_rack_logs_key_fetch_failures_as_401_and_recovers_without_restarting
    rsa, kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    output = StringIO.new
    teams = Teams::App.new(
      api: FakeApi.new, client_id: "client-id", client_secret: "secret", tenant_id: nil,
      dangerously_allow_unauthenticated_requests: false, cloud:, logger: Logger.new(output)
    )
    teams.instance_variable_set(:@jwt_validator, validator)
    handled = []
    teams.on_message { |ctx| handled << ctx.activity.id }
    request = Rack::MockRequest.new(teams.to_rack)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload.merge("serviceurl" => teams_payload["serviceUrl"]))
    options = { input: JSON.generate(teams_payload), "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer #{token}" }

    http.responses[keys_uri] = Net::ReadTimeout.new("JWKS unavailable")
    response = request.post("/api/messages", options)
    assert_equal 401, response.status
    assert_includes output.string, "Rejected Teams request (401)"
    assert_includes output.string, "JWKS unavailable"
    assert_empty handled

    http.responses[keys_uri] = { "keys" => [JwtTestHelper.jwk_for(rsa, kid:)] }
    assert_equal 200, request.post("/api/messages", options).status
    assert_equal ["activity-1"], handled
  end

  def test_inbound_activity_validates_service_tokens_like_validate
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(
      rsa:, kid:, payload: valid_payload.merge("serviceurl" => "https://smba.trafficmanager.net/teams")
    )
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    payload = validator.validate_inbound_activity!("Bearer #{token}", service_url: "https://smba.trafficmanager.net/teams")
    assert_equal "client-id", payload["aud"]
    error = assert_raises(Teams::AuthenticationError) do
      validator.validate_inbound_activity!("Bearer #{token}", service_url: "https://evil.example.com")
    end
    assert_includes error.message, "Service URL mismatch"
  end

  def test_inbound_activity_accepts_entra_agentic_token_without_serviceurl
    rsa, kid, cloud, http = validator_parts
    http.responses["https://login.example.com/tenant-x/discovery/v2.0/keys"] = {
      "keys" => [JwtTestHelper.jwk_for(rsa, kid:)]
    }
    token = JwtTestHelper.token(rsa:, kid:, payload: entra_payload)
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    payload = validator.validate_inbound_activity!("Bearer #{token}", service_url: "https://smba.trafficmanager.net/teams")
    assert_equal "tenant-x", payload["tid"]
  end

  def test_inbound_activity_accepts_entra_v1_issuer
    rsa, kid, cloud, http = validator_parts
    http.responses["https://login.example.com/tenant-x/discovery/v2.0/keys"] = {
      "keys" => [JwtTestHelper.jwk_for(rsa, kid:)]
    }
    token = JwtTestHelper.token(rsa:, kid:, payload: entra_payload.merge("iss" => "https://sts.windows.net/tenant-x/"))
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    payload = validator.validate_inbound_activity!("Bearer #{token}")
    assert_equal "https://sts.windows.net/tenant-x/", payload["iss"]
  end

  def test_inbound_activity_entra_token_requires_tid
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid:, payload: entra_payload.tap { |payload| payload.delete("tid") })
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate_inbound_activity!("Bearer #{token}") }
    assert_equal "Entra inbound token is missing tid", error.message
    assert_empty http.gets
  end

  def test_inbound_activity_entra_rejects_issuer_tenant_mismatch
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid:, payload: entra_payload.merge("tid" => "tenant-other"))
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate_inbound_activity!("Bearer #{token}") }
    assert_equal "JWT issuer is invalid", error.message
    assert_empty http.gets
  end

  def test_inbound_activity_entra_rejects_wrong_audience
    rsa, kid, cloud, http = validator_parts
    token = JwtTestHelper.token(rsa:, kid:, payload: entra_payload.merge("aud" => "other-client-id"))
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate_inbound_activity!("Bearer #{token}") }
    assert_equal "JWT audience is invalid", error.message
    assert_empty http.gets
  end

  def test_inbound_activity_entra_rejects_forged_signature
    rsa, kid, cloud, http = validator_parts
    http.responses["https://login.example.com/tenant-x/discovery/v2.0/keys"] = {
      "keys" => [JwtTestHelper.jwk_for(rsa, kid:)]
    }
    other_rsa = OpenSSL::PKey::RSA.generate(2048)
    token = JwtTestHelper.token(rsa: other_rsa, kid:, payload: entra_payload)
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)

    error = assert_raises(Teams::AuthenticationError) { validator.validate_inbound_activity!("Bearer #{token}") }
    assert_includes error.message, "Signature verification failed"
  end

  private

  def keys_uri
    "https://login.example.com/keys"
  end

  def age_cached_keys(validator, seconds:)
    provider = validator.instance_variable_get(:@jwks_loaders).fetch(keys_uri)
    entry = provider.cache.fetch(keys_uri)
    provider.cache.store(keys_uri, entry.merge(fetched_at: Time.now - seconds))
  end

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
    stub_request(:get, %r{\Ahttps://login\.example\.com/(?:keys|tenant-(?:1|x)/discovery/v2\.0/keys)\z}).to_return do |request|
      { status: 200, body: JSON.generate(http.get("#{cloud.login_endpoint}#{request.uri.path}")), headers: { "Content-Type" => "application/json" } }
    end

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

  def entra_payload
    {
      "iss" => "https://login.example.com/tenant-x/v2.0",
      "tid" => "tenant-x",
      "aud" => "client-id",
      "nbf" => Time.now.to_i - 60,
      "exp" => Time.now.to_i + 3600
    }
  end
end
