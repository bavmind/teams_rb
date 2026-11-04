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
    validator = clocked_validator(cloud:, http:)
    assert_equal "client-id", validator.validate!("Bearer #{token}")["aud"]

    validator.cache_time = 600
    http.responses[keys_uri]["keys"] << JwtTestHelper.jwk_for(rsa, kid: "second")
    assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
  end

  def test_fetches_unknown_key_immediately_after_cache_population
    rsa, kid, cloud, http = validator_parts
    rotated_rsa = OpenSSL::PKey::RSA.generate(2048)
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    validator.validate!("Bearer #{token}")

    http.responses[keys_uri] = { "keys" => [JwtTestHelper.jwk_for(rotated_rsa, kid: "rotated")] }
    rotated = JwtTestHelper.token(rsa: rotated_rsa, kid: "rotated", payload: valid_payload)

    assert_equal "client-id", validator.validate!("Bearer #{rotated}")["aud"]
    assert_equal "client-id", validator.validate!("Bearer #{token}")["aud"]
    assert_equal 2, http.gets.count(keys_uri)

    forged = JwtTestHelper.token(rsa:, kid: "rotated", payload: valid_payload)
    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{forged}") }
    assert_includes error.message, "Signature verification failed"
  end

  def test_caches_only_the_requested_key_not_the_entire_document
    rsa, kid, cloud, http = validator_parts
    http.responses[keys_uri]["keys"] << JwtTestHelper.jwk_for(rsa, kid: "second")
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    first = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    second = JwtTestHelper.token(rsa:, kid: "second", payload: valid_payload)

    validator.validate!("Bearer #{first}")
    validator.validate!("Bearer #{second}")
    validator.validate!("Bearer #{second}")

    assert_equal 2, http.gets.count(keys_uri)
  end

  def test_does_not_cache_or_rate_limit_missing_keys
    rsa, _kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    unknown = JwtTestHelper.token(rsa:, kid: "unknown", payload: valid_payload)

    12.times do
      assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{unknown}") }
    end
    assert_equal 12, http.gets.count(keys_uri)

    http.responses[keys_uri]["keys"] << JwtTestHelper.jwk_for(rsa, kid: "unknown")
    assert_equal "client-id", validator.validate!("Bearer #{unknown}")["aud"]
    assert_equal 13, http.gets.count(keys_uri)
  end

  def test_expires_keys_after_ten_minutes_without_extending_ttl_on_hits
    rsa, kid, cloud, http = validator_parts
    validator = clocked_validator(cloud:, http:)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    validator.validate!("Bearer #{token}")

    validator.cache_time = 599
    validator.validate!("Bearer #{token}")
    assert_equal 1, http.gets.count(keys_uri)

    http.responses[keys_uri] = { "keys" => [] }
    validator.cache_time = 600
    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    assert_equal "JWT signing key was not found", error.message
    assert_equal 2, http.gets.count(keys_uri)

    http.responses[keys_uri] = { "keys" => [JwtTestHelper.jwk_for(rsa, kid:)] }
    assert_equal "client-id", validator.validate!("Bearer #{token}")["aud"]
    assert_equal 3, http.gets.count(keys_uri)
  end

  def test_evicts_the_least_recently_used_key_after_five_entries_per_endpoint
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
    assert_equal 6, http.gets.count(keys_uri)

    validator.validate!("Bearer #{tokens[1]}")
    assert_equal 7, http.gets.count(keys_uri)
    validator.validate!("Bearer #{tenant_token}")
    assert_equal 1, http.gets.count(tenant_uri)
  end

  def test_failed_fetches_reject_authentication_without_stale_fallback_or_retry_delay
    rsa, kid, cloud, http = validator_parts
    validator = clocked_validator(cloud:, http:)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    validator.validate!("Bearer #{token}")
    http.responses[keys_uri] = Teams::HttpError.new("JWKS unavailable", status: 503, headers: {}, body: "")
    missing = JwtTestHelper.token(rsa:, kid: "missing", payload: valid_payload)

    error = assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{missing}") }
    assert_includes error.message, "JWKS unavailable"
    assert_equal "client-id", validator.validate!("Bearer #{token}")["aud"]

    validator.cache_time = 600
    assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    http.responses[keys_uri] = { "keys" => [JwtTestHelper.jwk_for(rsa, kid:)] }
    assert_equal "client-id", validator.validate!("Bearer #{token}")["aud"]
    assert_equal 4, http.gets.count(keys_uri)
  end

  def test_rejects_malformed_key_responses_and_retries_without_caching_errors
    rsa, kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    [nil, "not JSON", { "keys" => {} }, { "keys" => [{ "kid" => kid, "kty" => "RSA" }] }, Faraday::TimeoutError.new("timed out")].each do |response|
      http.responses[keys_uri] = response
      assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    end

    http.responses[keys_uri] = { "keys" => [JwtTestHelper.jwk_for(rsa, kid:)] }
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

  def test_concurrent_requests_share_a_successful_key_fetch
    rsa, kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    entered = Queue.new
    release = Queue.new
    document = http.responses[keys_uri]
    http.responses[keys_uri] = lambda do
      entered << true
      release.pop
      document
    end
    start = Queue.new
    threads = 8.times.map do
      Thread.new do
        start.pop
        validator.validate!("Bearer #{token}")
      end
    end
    8.times { start << true }

    assert entered.pop(timeout: 5), "JWKS fetch did not start"
    release << true
    assert_equal ["client-id"] * 8, threads.map { |thread| thread_value(thread)["aud"] }
    assert_equal 1, http.gets.count(keys_uri)
    assert_equal 1, http.gets.count(cloud.open_id_metadata_url)
  ensure
    release << true if release
    stop_threads(*threads) if threads
  end

  def test_cached_key_validation_does_not_wait_for_an_unknown_key_fetch
    rsa, kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    validator.validate!("Bearer #{token}")
    unknown = JwtTestHelper.token(rsa:, kid: "unknown", payload: valid_payload)
    entered = Queue.new
    release = Queue.new
    http.responses[keys_uri] = lambda do
      entered << true
      release.pop
      { "keys" => [] }
    end

    fetch_thread = Thread.new do
      assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{unknown}") }
    end
    assert entered.pop(timeout: 5), "JWKS fetch did not start"
    cached_thread = Thread.new { validator.validate!("Bearer #{token}") }

    assert_equal "client-id", thread_value(cached_thread)["aud"]
    assert_equal 2, http.gets.count(keys_uri)
    release << true
    assert_equal "JWT signing key was not found", thread_value(fetch_thread).message
  ensure
    release << true if release
    stop_threads(fetch_thread, cached_thread)
  end

  def test_cached_tenant_key_validation_does_not_wait_for_bot_framework_discovery
    rsa, kid, cloud, http = validator_parts
    tenant_uri = "#{cloud.login_endpoint}/tenant-1/discovery/v2.0/keys"
    http.responses[tenant_uri] = http.responses[keys_uri]
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", tenant_id: "tenant-1", cloud:, http:)
    tenant_token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload.merge("iss" => "https://sts.windows.net/tenant-1/"))
    validator.validate!("Bearer #{tenant_token}")
    bot_token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    entered = Queue.new
    release = Queue.new
    metadata = http.responses[cloud.open_id_metadata_url]
    http.responses[cloud.open_id_metadata_url] = lambda do
      entered << true
      release.pop
      metadata
    end

    discovery_thread = Thread.new { validator.validate!("Bearer #{bot_token}") }
    assert entered.pop(timeout: 5), "Discovery request did not start"
    cached_thread = Thread.new { validator.validate!("Bearer #{tenant_token}") }

    assert_equal "client-id", thread_value(cached_thread)["aud"]
    assert_equal 1, http.gets.count(tenant_uri)
    release << true
    assert_equal "client-id", thread_value(discovery_thread)["aud"]
    assert_equal 1, http.gets.count(cloud.open_id_metadata_url)
  ensure
    release << true if release
    stop_threads(discovery_thread, cached_thread)
  end

  def test_failed_concurrent_fetch_releases_waiters_for_immediate_retry
    rsa, kid, cloud, http = validator_parts
    validator = Teams::Auth::JwtValidator.new(client_id: "client-id", cloud:, http:)
    token = JwtTestHelper.token(rsa:, kid:, payload: valid_payload)
    entered = Queue.new
    release = Queue.new
    document = http.responses[keys_uri]
    attempts = 0
    http.responses[keys_uri] = lambda do
      attempts += 1
      if attempts == 1
        entered << true
        release.pop
        Teams::HttpError.new("JWKS unavailable", status: 503, headers: {}, body: "")
      else
        document
      end
    end

    failed_thread = Thread.new do
      assert_raises(Teams::AuthenticationError) { validator.validate!("Bearer #{token}") }
    end
    assert entered.pop(timeout: 5), "JWKS fetch did not start"
    retry_thread = Thread.new { validator.validate!("Bearer #{token}") }
    release << true

    assert_includes thread_value(failed_thread).message, "JWKS unavailable"
    assert_equal "client-id", thread_value(retry_thread)["aud"]
    assert_equal "client-id", validator.validate!("Bearer #{token}")["aud"]
    assert_equal 2, http.gets.count(keys_uri)
  ensure
    release << true if release
    stop_threads(failed_thread, retry_thread)
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

    http.responses[keys_uri] = Teams::HttpError.new("JWKS unavailable", status: 503, headers: {}, body: "")
    response = request.post("/api/messages", options)
    assert_equal 401, response.status
    assert_includes output.string, "Rejected Teams request (401)"
    assert_includes output.string, "JWKS unavailable"
    assert_empty handled

    http.responses[keys_uri] = { "keys" => [JwtTestHelper.jwk_for(rsa, kid:)] }
    assert_equal 200, request.post("/api/messages", options).status
    assert_equal ["activity-1"], handled
  end

  private

  def thread_value(thread)
    assert thread.join(5), "Timed out waiting for JWT verification"
    thread.value
  end

  def stop_threads(*threads)
    threads.compact.each do |thread|
      thread.kill if thread.alive?
      thread.join
    end
  end

  def keys_uri
    "https://login.example.com/keys"
  end

  def clocked_validator(cloud:, http:)
    klass = Class.new(Teams::Auth::JwtValidator) do
      attr_accessor :cache_time

      private

      def monotonic_time
        cache_time
      end
    end
    validator = klass.new(client_id: "client-id", cloud:, http:)
    validator.cache_time = 0
    validator
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
