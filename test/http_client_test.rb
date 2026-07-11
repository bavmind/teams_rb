# frozen_string_literal: true

require_relative "test_helper"

class HttpClientTest < Minitest::Test
  def test_resolves_token_once_per_request
    calls = 0
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ok") do |env|
        assert_equal "Bearer token-1", env.request_headers["Authorization"]
        [200, { "Content-Type" => "application/json" }, "{}"]
      end
    end
    connection = Faraday.new(url: "https://example.test") do |faraday|
      faraday.adapter :test, stubs
    end
    client = Teams::Common::HttpClient.new(
      connection:,
      token: -> {
        calls += 1
        "token-#{calls}"
      }
    )

    client.get("/ok")

    assert_equal 1, calls
    stubs.verify_stubbed_calls
  end

  def test_non_json_error_response_raises_http_error_with_raw_body
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/broken") { [502, { "Content-Type" => "text/html" }, "<html>Bad Gateway</html>"] }
    end
    connection = Faraday.new(url: "https://example.test") do |faraday|
      faraday.adapter :test, stubs
    end
    client = Teams::Common::HttpClient.new(connection:)

    error = assert_raises(Teams::HttpError) { client.get("/broken") }

    assert_equal 502, error.status
    assert_equal "<html>Bad Gateway</html>", error.body
    assert_includes error.message, "502"
    stubs.verify_stubbed_calls
  end

  def test_json_error_response_raises_http_error_with_parsed_body
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/rejected") do
        [400, { "Content-Type" => "application/json" }, JSON.generate("error" => { "message" => "BadSyntax" })]
      end
    end
    connection = Faraday.new(url: "https://example.test") do |faraday|
      faraday.adapter :test, stubs
    end
    client = Teams::Common::HttpClient.new(connection:)

    error = assert_raises(Teams::HttpError) { client.get("/rejected") }

    assert_equal 400, error.status
    assert_equal "BadSyntax", error.body.dig("error", "message")
    stubs.verify_stubbed_calls
  end
end
