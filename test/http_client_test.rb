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
end
