# frozen_string_literal: true

require_relative "test_helper"

class GraphClientTest < Minitest::Test
  def test_gets_resource
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/v1.0/me") do |env|
        assert_equal "Bearer graph-token", env.request_headers["Authorization"]

        [200, { "Content-Type" => "application/json" }, JSON.generate(
          "displayName" => "Test User", "userPrincipalName" => "test@example.com"
        )]
      end
    end
    client = graph_client(stubs)

    me = client.get("/me")

    assert_equal "Test User", me["displayName"]
    stubs.verify_stubbed_calls
  end

  def test_posts_with_symbol_key_body
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1.0/me/sendMail") do |env|
        assert_equal "Hello", JSON.parse(env.body).dig("message", "subject")

        [202, {}, ""]
      end
    end
    client = graph_client(stubs)

    assert_nil client.post("me/sendMail", json: { message: { subject: "Hello" } })
    stubs.verify_stubbed_calls
  end

  def test_patch_and_delete
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.patch("/v1.0/me") do |env|
        assert_equal({ "jobTitle" => "Rubyist" }, JSON.parse(env.body))
        [204, {}, ""]
      end
      stub.delete("/v1.0/me/messages/msg-1") { [204, {}, ""] }
    end
    client = graph_client(stubs)

    assert_nil client.patch("/me", json: { "jobTitle" => "Rubyist" })
    assert_nil client.delete("/me/messages/msg-1")
    stubs.verify_stubbed_calls
  end

  def test_graph_errors_are_typed_with_code_and_body
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/v1.0/users") do
        [403, { "Content-Type" => "application/json" }, JSON.generate(
          "error" => { "code" => "Authorization_RequestDenied", "message" => "Insufficient privileges" }
        )]
      end
    end
    client = graph_client(stubs)

    error = assert_raises(Teams::GraphError) { client.get("/users") }

    assert_equal 403, error.status
    assert_equal "Authorization_RequestDenied", error.code
    assert_includes error.message, "Insufficient privileges"
    assert_equal "Insufficient privileges", error.body.dig("error", "message")
  end

  def test_sovereign_base_url_root
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/v1.0/me") { [200, { "Content-Type" => "application/json" }, "{}"] }
    end
    connection = Faraday.new(url: "https://graph.microsoft.us") do |faraday|
      faraday.adapter :test, stubs
    end
    client = Teams::Graph::Client.new(
      token: "t",
      base_url_root: "https://graph.microsoft.us",
      http: Teams::Common::HttpClient.new(connection:, token: "t")
    )

    assert_equal "https://graph.microsoft.us", client.base_url_root
    client.get("/me")
    stubs.verify_stubbed_calls
  end

  def test_app_exposes_app_identity_graph_client
    teams = Teams::App.new(api: FakeApi.new, skip_auth: true, logger: Logger.new(StringIO.new))

    assert_instance_of Teams::Graph::Client, teams.graph
    assert_equal "https://graph.microsoft.com", teams.graph.base_url_root
  end

  private

  def graph_client(stubs)
    connection = Faraday.new(url: "https://graph.microsoft.com") do |faraday|
      faraday.adapter :test, stubs
    end

    Teams::Graph::Client.new(
      token: "graph-token",
      http: Teams::Common::HttpClient.new(connection:, token: "graph-token")
    )
  end
end
