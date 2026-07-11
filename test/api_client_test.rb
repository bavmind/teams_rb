# frozen_string_literal: true

require_relative "test_helper"

class ApiClientTest < Minitest::Test
  def test_exposes_conversations_client
    api = Teams::Api::Client.new(
      service_url: "https://smba.trafficmanager.net/teams",
      http: Teams::Common::HttpClient.new
    )

    assert_instance_of Teams::Api::ConversationClient, api.conversations
    assert_same api.conversations, api.conversations
  end

  def test_creates_conversation
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/teams/v3/conversations") do |env|
        assert_equal(
          {
            "members" => [{ "id" => "user-1", "name" => "User One" }],
            "tenantId" => "tenant-1",
            "activity" => { "type" => "message", "text" => "hello" }
          },
          JSON.parse(env.body)
        )

        [201, { "Content-Type" => "application/json" }, JSON.generate("id" => "conversation-9", "activityId" => "activity-9")]
      end
    end
    client = api_client(stubs)

    conversation = client.create(
      members: [Teams::Api::Account.new("id" => "user-1", "name" => "User One")],
      tenant_id: "tenant-1",
      activity: "hello"
    )

    assert_instance_of Teams::Api::ConversationResource, conversation
    assert_equal "conversation-9", conversation.id
    assert_equal "activity-9", conversation.activity_id
    stubs.verify_stubbed_calls
  end

  def test_creates_conversation_with_symbol_key_members
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/teams/v3/conversations") do |env|
        assert_equal({ "members" => [{ "id" => "user-1" }] }, JSON.parse(env.body))

        [201, { "Content-Type" => "application/json" }, JSON.generate("id" => "conversation-9")]
      end
    end
    client = api_client(stubs)

    client.create(members: [{ id: "user-1" }])
    stubs.verify_stubbed_calls
  end

  def test_gets_members_and_normalizes_object_id
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/teams/v3/conversations/conversation-1/members") do
        [200, { "Content-Type" => "application/json" }, JSON.generate([
          { "id" => "user-1", "name" => "User One", "objectId" => "aad-1" },
          { "id" => "user-2", "name" => "User Two", "aadObjectId" => "aad-2" }
        ])]
      end
    end
    client = api_client(stubs)

    members = client.get_members("conversation-1")

    assert_equal 2, members.length
    assert_instance_of Teams::Api::Account, members.first
    assert_equal %w[aad-1 aad-2], members.map(&:aad_object_id)
    stubs.verify_stubbed_calls
  end

  def test_gets_member_by_id
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/teams/v3/conversations/a%3A1/members/user+1") do
        [200, { "Content-Type" => "application/json" }, JSON.generate(
          "id" => "user 1", "name" => "User One", "email" => "user@example.com"
        )]
      end
    end
    client = api_client(stubs)

    member = client.get_member_by_id("a:1", "user 1")

    assert_instance_of Teams::Api::Account, member
    assert_equal "user@example.com", member.email
    stubs.verify_stubbed_calls
  end

  def test_gets_paged_members
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/teams/v3/conversations/conversation-1/pagedMembers?pageSize=100&continuationToken=token-1") do |env|
        assert_equal "100", env.params["pageSize"]
        assert_equal "token-1", env.params["continuationToken"]

        [200, { "Content-Type" => "application/json" }, JSON.generate(
          "members" => [{ "id" => "user-1", "objectId" => "aad-1" }],
          "continuationToken" => "token-2"
        )]
      end
    end
    client = api_client(stubs)

    page = client.get_paged_members("conversation-1", page_size: 100, continuation_token: "token-1")

    assert_instance_of Teams::Api::PagedMembersResult, page
    assert_equal "token-2", page.continuation_token
    assert_equal "aad-1", page.members.first.aad_object_id
    stubs.verify_stubbed_calls
  end

  def test_gets_paged_members_without_params
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/teams/v3/conversations/conversation-1/pagedMembers") do
        [200, { "Content-Type" => "application/json" }, JSON.generate("members" => [])]
      end
    end
    client = api_client(stubs)

    page = client.get_paged_members("conversation-1")

    assert_empty page.members
    assert_nil page.continuation_token
    stubs.verify_stubbed_calls
  end

  def test_gets_activity_members
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/teams/v3/conversations/conversation-1/activities/activity-1/members") do
        [200, { "Content-Type" => "application/json" }, JSON.generate([
          { "id" => "user-1", "objectId" => "aad-1" }
        ])]
      end
    end
    client = api_client(stubs)

    members = client.get_activity_members("conversation-1", "activity-1")

    assert_equal ["aad-1"], members.map(&:aad_object_id)
    stubs.verify_stubbed_calls
  end

  def test_creates_activity
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/teams/v3/conversations/conversation-1/activities") do |env|
        assert_equal(
          { "type" => "message", "text" => "hello" },
          JSON.parse(env.body)
        )

        [201, { "Content-Type" => "application/json" }, JSON.generate("id" => "created-1")]
      end
    end
    client = api_client(stubs)

    assert_equal(
      { "id" => "created-1" },
      client.create_activity("conversation-1", "hello")
    )
    stubs.verify_stubbed_calls
  end

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
      client.create_targeted_activity("conversation-1", "secret")
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
    ).conversations
  end
end
