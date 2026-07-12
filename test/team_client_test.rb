# frozen_string_literal: true

require_relative "test_helper"

class TeamClientTest < Minitest::Test
  def test_gets_team_by_id
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/teams/v3/teams/19%3Ateam%40thread.tacv2") do
        [200, { "Content-Type" => "application/json" }, JSON.generate(
          "id" => "19:team@thread.tacv2",
          "name" => "Engineering",
          "type" => "standard",
          "aadGroupId" => "aad-group-1",
          "channelCount" => 3,
          "memberCount" => 12,
          "tenantId" => "tenant-1"
        )]
      end
    end
    client = team_client(stubs)

    team = client.get_by_id("19:team@thread.tacv2")

    assert_instance_of Teams::Api::TeamDetails, team
    assert_equal "Engineering", team.name
    assert_equal "standard", team.type
    assert_equal "aad-group-1", team.aad_group_id
    assert_equal 3, team.channel_count
    assert_equal 12, team.member_count
    assert_equal "tenant-1", team.tenant_id
    stubs.verify_stubbed_calls
  end

  def test_gets_team_conversations
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/teams/v3/teams/team-1/conversations") do
        [200, { "Content-Type" => "application/json" }, JSON.generate(
          "conversations" => [
            { "id" => "19:general@thread.tacv2", "name" => "General", "type" => "standard" },
            { "id" => "19:private@thread.tacv2", "name" => "Leads", "type" => "private" }
          ]
        )]
      end
    end
    client = team_client(stubs)

    channels = client.get_conversations("team-1")

    assert_equal 2, channels.length
    assert_instance_of Teams::Api::ChannelInfo, channels.first
    assert_equal %w[General Leads], channels.map(&:name)
    assert_equal "private", channels.last.type
    stubs.verify_stubbed_calls
  end

  def test_api_client_exposes_teams_client
    api = Teams::Api::Client.new(
      service_url: "https://smba.trafficmanager.net/teams",
      http: Teams::Common::HttpClient.new
    )

    assert_instance_of Teams::Api::TeamClient, api.teams
    assert_same api.teams, api.teams
  end

  private

  def team_client(stubs)
    connection = Faraday.new(url: "https://smba.trafficmanager.net/teams") do |faraday|
      faraday.adapter :test, stubs
    end

    Teams::Api::Client.new(
      service_url: "https://smba.trafficmanager.net/teams",
      http: Teams::Common::HttpClient.new(connection:)
    ).teams
  end
end
