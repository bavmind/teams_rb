# frozen_string_literal: true

require_relative "test_helper"

class MeetingClientTest < Minitest::Test
  def test_gets_meeting_by_id
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/teams/v1/meetings/meeting-1") do
        [200, { "Content-Type" => "application/json" }, JSON.generate(
          "id" => "meeting-1",
          "details" => { "title" => "Standup", "joinUrl" => "https://teams.microsoft.com/l/meetup-join/x" },
          "conversation" => { "id" => "conversation-1", "conversationType" => "groupChat" },
          "organizer" => { "id" => "user-1", "aadObjectId" => "aad-1" }
        )]
      end
    end
    client = meeting_client(stubs)

    meeting = client.get_by_id("meeting-1")

    assert_instance_of Teams::Api::MeetingInfo, meeting
    assert_equal "meeting-1", meeting.id
    assert_equal "conversation-1", meeting.conversation.id
    assert_equal "aad-1", meeting.organizer.aad_object_id
    stubs.verify_stubbed_calls
  end

  def test_gets_participant_with_tenant_id
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/teams/v1/meetings/meeting+1/participants/aad-1?tenantId=tenant-1") do |env|
        assert_equal "tenant-1", env.params["tenantId"]

        [200, { "Content-Type" => "application/json" }, JSON.generate(
          "user" => { "id" => "user-1", "aadObjectId" => "aad-1" },
          "meeting" => { "role" => "Presenter", "inMeeting" => true },
          "conversation" => { "id" => "conversation-1" }
        )]
      end
    end
    client = meeting_client(stubs)

    participant = client.get_participant("meeting 1", "aad-1", "tenant-1")

    assert_instance_of Teams::Api::MeetingParticipant, participant
    assert_equal "user-1", participant.user.id
    assert_equal "Presenter", participant.meeting.role
    assert participant.meeting.in_meeting
    assert_equal "conversation-1", participant.conversation.id
    stubs.verify_stubbed_calls
  end

  def test_send_notification_defaults_type_and_returns_nil_on_success
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/teams/v1/meetings/meeting-1/notification") do |env|
        body = JSON.parse(env.body)
        assert_equal "targetedMeetingNotification", body["type"]
        assert_equal ["aad-1"], body.dig("value", "recipients")

        [202, {}, ""]
      end
    end
    client = meeting_client(stubs)

    response = client.send_notification(
      "meeting-1",
      { value: { recipients: ["aad-1"], surfaces: [{ surface: "meetingStage" }] } }
    )

    assert_nil response
    stubs.verify_stubbed_calls
  end

  def test_send_notification_returns_failures_on_partial_success
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/teams/v1/meetings/meeting-1/notification") do
        [207, { "Content-Type" => "application/json" }, JSON.generate(
          "recipientsFailureInfo" => [
            { "recipientMri" => "mri-1", "errorCode" => "MemberNotFoundInConversation", "failureReason" => "not found" }
          ]
        )]
      end
    end
    client = meeting_client(stubs)

    response = client.send_notification("meeting-1", { "value" => { "recipients" => ["aad-1"], "surfaces" => [] } })

    assert_instance_of Teams::Api::MeetingNotificationResponse, response
    failure = response.recipients_failure_info.first
    assert_equal "mri-1", failure.recipient_mri
    assert_equal "MemberNotFoundInConversation", failure.error_code
    assert_equal "not found", failure.failure_reason
    stubs.verify_stubbed_calls
  end

  def test_api_client_exposes_meetings_client
    api = Teams::Api::Client.new(
      service_url: "https://smba.trafficmanager.net/teams",
      http: Teams::Common::HttpClient.new
    )

    assert_instance_of Teams::Api::MeetingClient, api.meetings
    assert_same api.meetings, api.meetings
  end

  private

  def meeting_client(stubs)
    connection = Faraday.new(url: "https://smba.trafficmanager.net/teams") do |faraday|
      faraday.adapter :test, stubs
    end

    Teams::Api::Client.new(
      service_url: "https://smba.trafficmanager.net/teams",
      http: Teams::Common::HttpClient.new(connection:)
    ).meetings
  end
end
