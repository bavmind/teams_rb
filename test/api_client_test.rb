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

  def test_reply_to_activity_sets_reply_to_id_in_body
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/teams/v3/conversations/conversation-1/activities/activity-1") do |env|
        body = JSON.parse(env.body)
        assert_equal "activity-1", body["replyToId"]
        assert_equal "reply text", body["text"]

        [201, { "Content-Type" => "application/json" }, JSON.generate("id" => "reply-1")]
      end
    end
    client = api_client(stubs)

    client.reply_to_activity("conversation-1", "activity-1", "reply text")
    stubs.verify_stubbed_calls
  end

  def test_sends_targeted_activity_with_query_param
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/teams/v3/conversations/conversation-1/activities?isTargetedActivity=true") do |env|
        assert_equal "true", env.params["isTargetedActivity"]

        [201, { "Content-Type" => "application/json" }, JSON.generate("id" => "targeted-1")]
      end
    end
    client = api_client(stubs)

    assert_equal(
      { "id" => "targeted-1" },
      client.send_targeted_to_conversation("conversation-1", "secret")
    )
    stubs.verify_stubbed_calls
  end

  def test_updates_targeted_activity_with_query_param
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.put("/teams/v3/conversations/conversation-1/activities/activity-1?isTargetedActivity=true") do
        [200, { "Content-Type" => "application/json" }, JSON.generate("id" => "activity-1")]
      end
    end
    client = api_client(stubs)

    client.update_targeted_activity("conversation-1", "activity-1", "updated")
    stubs.verify_stubbed_calls
  end

  def test_deletes_targeted_activity_with_query_param
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.delete("/teams/v3/conversations/conversation-1/activities/activity-1?isTargetedActivity=true") do
        [200, {}, ""]
      end
    end
    client = api_client(stubs)

    assert_nil client.delete_targeted_activity("conversation-1", "activity-1")
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
