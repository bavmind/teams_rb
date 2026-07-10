# frozen_string_literal: true

require_relative "test_helper"

class ApiClientTest < Minitest::Test
  def test_updates_activity
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.put("/teams/v3/conversations/conversation-1/activities/activity-1") do |env|
        assert_equal(
          { "type" => "message", "text" => "updated" },
          JSON.parse(env.body)
        )

        [200, { "Content-Type" => "application/json" }, JSON.generate("id" => "activity-1")]
      end
    end
    client = api_client(stubs)

    assert_equal(
      { "id" => "activity-1" },
      client.update_activity("conversation-1", "activity-1", "updated")
    )
    stubs.verify_stubbed_calls
  end

  def test_escapes_update_activity_path_values
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.put("/teams/v3/conversations/a%3A1/activities/activity+1") do
        [200, { "Content-Type" => "application/json" }, JSON.generate("id" => "activity 1")]
      end
    end
    client = api_client(stubs)

    client.update_activity("a:1", "activity 1", "updated")
    stubs.verify_stubbed_calls
  end

  def test_deletes_activity
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.delete("/teams/v3/conversations/conversation-1/activities/activity-1") do |env|
        assert_nil env.body

        [200, {}, ""]
      end
    end
    client = api_client(stubs)

    assert_nil client.delete_activity("conversation-1", "activity-1")
    stubs.verify_stubbed_calls
  end

  def test_escapes_delete_activity_path_values
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.delete("/teams/v3/conversations/a%3A1/activities/activity+1") do
        [200, {}, ""]
      end
    end
    client = api_client(stubs)

    client.delete_activity("a:1", "activity 1")
    stubs.verify_stubbed_calls
  end

  private

  def api_client(stubs)
    connection = Faraday.new(url: "https://smba.trafficmanager.net/teams") do |faraday|
      faraday.adapter :test, stubs
    end

    Teams::Api::Client.new(
      service_url: "https://smba.trafficmanager.net/teams",
      http: Teams::Common::HttpClient.new(connection:)
    )
  end
end
