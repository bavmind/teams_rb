# frozen_string_literal: true

require_relative "test_helper"

class ReactionClientTest < Minitest::Test
  def test_api_client_exposes_reactions_client
    api = Teams::Api::Client.new(
      service_url: "https://smba.trafficmanager.net/teams",
      http: Teams::Common::HttpClient.new
    )

    assert_instance_of Teams::Api::ReactionClient, api.reactions
    assert_same api.reactions, api.reactions
  end

  def test_adds_reaction
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.put("/teams/v3/conversations/conversation-1/activities/activity-1/reactions/like") do
        [200, { "Content-Type" => "application/json" }, ""]
      end
    end
    client = reaction_client(stubs)

    assert_nil client.add("conversation-1", "activity-1", "like")
    stubs.verify_stubbed_calls
  end

  def test_deletes_reaction
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.delete("/teams/v3/conversations/conversation-1/activities/activity-1/reactions/like") do
        [200, { "Content-Type" => "application/json" }, ""]
      end
    end
    client = reaction_client(stubs)

    assert_nil client.delete("conversation-1", "activity-1", "like")
    stubs.verify_stubbed_calls
  end

  def test_escapes_path_values
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.put("/teams/v3/conversations/a%3A1/activities/activity+1/reactions/heart%2Beyes") do
        [200, { "Content-Type" => "application/json" }, ""]
      end
    end
    client = reaction_client(stubs)

    client.add("a:1", "activity 1", "heart+eyes")
    stubs.verify_stubbed_calls
  end

  private

  def reaction_client(stubs)
    connection = Faraday.new(url: "https://smba.trafficmanager.net/teams") do |faraday|
      faraday.adapter :test, stubs
    end
    http = Teams::Common::HttpClient.new(connection:)

    Teams::Api::ReactionClient.new(
      service_url: "https://smba.trafficmanager.net/teams",
      http:
    )
  end
end
