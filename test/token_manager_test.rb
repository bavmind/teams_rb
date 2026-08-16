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

  def test_concurrent_bot_token_requests_fetch_once
    token_url = "https://login.microsoftonline.com/tenant/oauth2/v2.0/token"
    token = unsigned_token(exp: Time.now.to_i + 3600)
    http = FakeHttp.new(
      token_url => lambda do
        # Widen the race window so unsynchronized threads would stampede.
        sleep 0.02
        { "access_token" => token }
      end
    )
    manager = Teams::Auth::TokenManager.from_env(
      client_id: "client-id",
      client_secret: "secret",
      tenant_id: "tenant",
      http:
    )

    results = Array.new(8) { Thread.new { manager.bot_token } }.map(&:value)

    assert(results.all? { |value| value == token })
    assert_equal 1, http.posts.size
  end

  def test_requires_credentials
    manager = Teams::Auth::TokenManager.from_env(client_id: nil, client_secret: nil, tenant_id: nil)

    assert_raises(Teams::ConfigurationError) { manager.bot_token }
  end

  # Agentic token exchange request shapes. The wire forms reproduce MSAL's
  # documented parameters and are pinned here; they still need verification
  # against a live Agent 365 tenant before release.
  def test_agentic_app_token_runs_two_step_exchange
    http, manager, token = agentic_parts

    result = manager.agentic_app_token("https://botapi.skype.com/.default", agentic_app_id: "app-inst-1")

    assert_equal token, result
    assert_equal 2, http.posts.size

    step1 = URI.decode_www_form(http.posts[0][1][:body]).to_h
    assert_equal "client_credentials", step1["grant_type"]
    assert_equal "client-id", step1["client_id"]
    assert_equal "secret", step1["client_secret"]
    assert_equal "api://AzureADTokenExchange/.default", step1["scope"]
    assert_equal "app-inst-1", step1["fmi_path"]

    step2 = URI.decode_www_form(http.posts[1][1][:body]).to_h
    assert_equal "client_credentials", step2["grant_type"]
    assert_equal "app-inst-1", step2["client_id"]
    assert_equal "urn:ietf:params:oauth:client-assertion-type:jwt-bearer", step2["client_assertion_type"]
    assert_equal token, step2["client_assertion"]
    assert_equal "https://botapi.skype.com/.default", step2["scope"]
    refute step2.key?("client_secret")
  end

  def test_agentic_user_token_runs_three_step_exchange
    http, manager, token = agentic_parts

    result = manager.agentic_user_token(
      "https://botapi.skype.com/.default",
      agentic_app_id: "app-inst-1",
      agentic_user_id: "user-obj-1"
    )

    assert_equal token, result
    assert_equal 3, http.posts.size

    step2 = URI.decode_www_form(http.posts[1][1][:body]).to_h
    assert_equal "api://AzureADTokenExchange/.default", step2["scope"]

    step3 = URI.decode_www_form(http.posts[2][1][:body]).to_h
    assert_equal "urn:ietf:params:oauth:grant-type:jwt-bearer", step3["grant_type"]
    assert_equal "app-inst-1", step3["client_id"]
    assert_equal token, step3["client_assertion"]
    assert_equal token, step3["assertion"]
    assert_equal "on_behalf_of", step3["requested_token_use"]
    assert_equal "user-obj-1", step3["user_object_id"]
    assert_equal "https://botapi.skype.com/.default", step3["scope"]
  end

  def test_agentic_tokens_are_cached
    http, manager, _token = agentic_parts

    manager.agentic_app_token("https://botapi.skype.com/.default", agentic_app_id: "app-inst-1")
    manager.agentic_app_token("https://botapi.skype.com/.default", agentic_app_id: "app-inst-1")

    assert_equal 2, http.posts.size
  end

  def test_agentic_tokens_require_tenant
    _http, manager, _token = agentic_parts(tenant_id: nil)

    error = assert_raises(ArgumentError) do
      manager.agentic_app_token("https://botapi.skype.com/.default", agentic_app_id: "app-inst-1")
    end
    assert_equal "tenant_id is required for agentic tokens", error.message
  end

  def test_agentic_user_token_requires_ids
    _http, manager, _token = agentic_parts

    assert_raises(ArgumentError) do
      manager.agentic_user_token("scope", agentic_app_id: nil, agentic_user_id: "user-obj-1")
    end
    assert_raises(ArgumentError) do
      manager.agentic_user_token("scope", agentic_app_id: "app-inst-1", agentic_user_id: nil)
    end
  end

  def test_agentic_token_error_surfaces_description
    http, manager, _token = agentic_parts
    http.responses["https://login.microsoftonline.com/tenant/oauth2/v2.0/token"] = {
      "error" => "invalid_grant", "error_description" => "FMI path rejected"
    }

    error = assert_raises(Teams::Error) do
      manager.agentic_app_token("https://botapi.skype.com/.default", agentic_app_id: "app-inst-1")
    end
    assert_includes error.message, "Agent token exchange step 1 failed"
    assert_includes error.message, "FMI path rejected"
  end

  private

  def agentic_parts(tenant_id: "tenant")
    token = unsigned_token(exp: Time.now.to_i + 3600)
    http = FakeHttp.new(
      "https://login.microsoftonline.com/tenant/oauth2/v2.0/token" => { "access_token" => token }
    )
    manager = Teams::Auth::TokenManager.from_env(
      client_id: "client-id",
      client_secret: "secret",
      tenant_id:,
      http:
    )
    [http, manager, token]
  end

  def unsigned_token(exp:)
    JwtTestHelper.b64(JSON.generate({ "alg" => "none" })) +
      "." +
      JwtTestHelper.b64(JSON.generate({ "exp" => exp })) +
      "."
  end
end
