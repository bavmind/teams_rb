# frozen_string_literal: true

require_relative "test_helper"

class UserClientTest < Minitest::Test
  def test_gets_user_token
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/usertoken/GetToken?userId=user-1&connectionName=graph&channelId=msteams") do |env|
        assert_equal "user-1", env.params["userId"]
        assert_equal "graph", env.params["connectionName"]

        [200, { "Content-Type" => "application/json" }, JSON.generate(
          "connectionName" => "graph", "token" => "user-token-1", "expiration" => "2026-07-12T10:00:00Z"
        )]
      end
    end
    client = user_client(stubs)

    token = client.get_token(user_id: "user-1", connection_name: "graph", channel_id: "msteams")

    assert_instance_of Teams::Api::TokenResponse, token
    assert_equal "user-token-1", token.token
    assert_equal "graph", token.connection_name
    stubs.verify_stubbed_calls
  end

  def test_get_aad_tokens_uses_repeated_resource_url_params
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/api/usertoken/GetAadTokens") do |env|
        # Repeated plain resourceUrls keys on the wire, like TS/PY clients.
        assert_includes env.url.query, "resourceUrls=https%3A%2F%2Fgraph.microsoft.com&resourceUrls=https%3A%2F%2Fexample.com"
        assert_includes env.url.query, "userId=user-1"
        [200, { "Content-Type" => "application/json" }, JSON.generate(
          "https://graph.microsoft.com" => { "connectionName" => "graph", "token" => "graph-token" },
          "https://example.com" => { "connectionName" => "graph", "token" => "example-token" }
        )]
      end
    end
    client = user_client(stubs)

    tokens = client.get_aad_tokens(
      user_id: "user-1",
      connection_name: "graph",
      resource_urls: ["https://graph.microsoft.com", "https://example.com"],
      channel_id: "msteams"
    )

    assert_equal "graph-token", tokens["https://graph.microsoft.com"].token
    assert_equal "example-token", tokens["https://example.com"].token
    stubs.verify_stubbed_calls
  end

  def test_gets_token_status
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/usertoken/GetTokenStatus?userId=user-1&channelId=msteams") do
        [200, { "Content-Type" => "application/json" }, JSON.generate([
          { "channelId" => "msteams", "connectionName" => "graph", "hasToken" => true,
            "serviceProviderDisplayName" => "Azure Active Directory" }
        ])]
      end
    end
    client = user_client(stubs)

    statuses = client.get_token_status(user_id: "user-1", channel_id: "msteams")

    assert_equal 1, statuses.length
    assert statuses.first.has_token
    assert_equal "Azure Active Directory", statuses.first.service_provider_display_name
    stubs.verify_stubbed_calls
  end

  def test_signs_out
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.delete("/api/usertoken/SignOut?userId=user-1&connectionName=graph&channelId=msteams") do
        [200, {}, ""]
      end
    end
    client = user_client(stubs)

    assert_nil client.sign_out(user_id: "user-1", connection_name: "graph", channel_id: "msteams")
    stubs.verify_stubbed_calls
  end

  def test_exchanges_token_with_body
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/api/usertoken/exchange?userId=user-1&connectionName=graph&channelId=msteams") do |env|
        assert_equal({ "token" => "exchangeable-token" }, JSON.parse(env.body))

        [200, { "Content-Type" => "application/json" }, JSON.generate(
          "connectionName" => "graph", "token" => "exchanged-token"
        )]
      end
    end
    client = user_client(stubs)

    token = client.exchange_token(
      user_id: "user-1", connection_name: "graph", channel_id: "msteams",
      exchange_request: { token: "exchangeable-token" }
    )

    assert_equal "exchanged-token", token.token
    stubs.verify_stubbed_calls
  end

  def test_bot_sign_in_resource
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/botsignin/GetSignInResource?state=c3RhdGU%3D") do
        [200, { "Content-Type" => "application/json" }, JSON.generate(
          "signInLink" => "https://token.botframework.com/signin?x=1",
          "tokenExchangeResource" => { "id" => "res-1", "uri" => "api://botid-x/scope" },
          "tokenPostResource" => { "sasUrl" => "https://token.botframework.com/sas" }
        )]
      end
    end
    api = api_hub(stubs)

    resource = api.bots.sign_in.get_resource(state: "c3RhdGU=")

    assert_instance_of Teams::Api::SignInUrlResponse, resource
    assert_equal "https://token.botframework.com/signin?x=1", resource.sign_in_link
    assert_equal "api://botid-x/scope", resource.token_exchange_resource.uri
    assert_equal "https://token.botframework.com/sas", resource.token_post_resource.sas_url
    stubs.verify_stubbed_calls
  end

  def test_bot_sign_in_url_returns_plain_string
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/botsignin/GetSignInUrl?state=abc") do
        [200, { "Content-Type" => "text/plain" }, "https://token.botframework.com/signin?state=abc"]
      end
    end
    api = api_hub(stubs)

    assert_equal "https://token.botframework.com/signin?state=abc", api.bots.sign_in.get_url(state: "abc")
    stubs.verify_stubbed_calls
  end

  def test_api_client_exposes_users_and_bots
    api = Teams::Api::Client.new(
      service_url: "https://smba.trafficmanager.net/teams",
      http: Teams::Common::HttpClient.new
    )

    assert_instance_of Teams::Api::UserClient, api.users
    assert_instance_of Teams::Api::BotSignInClient, api.bots.sign_in
  end

  private

  def api_hub(stubs)
    connection = Faraday.new(url: "https://token.botframework.com") do |faraday|
      faraday.options.params_encoder = Faraday::FlatParamsEncoder
      faraday.adapter :test, stubs
    end

    Teams::Api::Client.new(
      service_url: "https://smba.trafficmanager.net/teams",
      http: Teams::Common::HttpClient.new(connection:),
      oauth_url: "https://token.botframework.com"
    )
  end

  def user_client(stubs)
    api_hub(stubs).users
  end
end
