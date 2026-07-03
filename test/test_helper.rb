# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "rack/test"
require "json"
require "openssl"
require "base64"
require "stringio"
require "teams"

class FakeApi
  attr_reader :service_url, :sent, :replies, :updates

  def initialize(service_url: "https://smba.trafficmanager.net/teams")
    @service_url = service_url
    @sent = []
    @replies = []
    @updates = []
  end

  def send_to_conversation(conversation_id, activity, service_url: nil)
    payload = activity.respond_to?(:to_h) ? activity.to_h : activity
    snapshot = Marshal.load(Marshal.dump(payload))
    @sent << [conversation_id, snapshot, service_url]
    { "id" => stream_id_for(payload) || "sent-#{@sent.length}" }
  end

  def reply_to_activity(conversation_id, activity_id, activity, service_url: nil)
    payload = activity.respond_to?(:to_h) ? activity.to_h : activity
    snapshot = Marshal.load(Marshal.dump(payload))
    @replies << [conversation_id, activity_id, snapshot, service_url]
    { "id" => "reply-id" }
  end

  def update_activity(conversation_id, activity_id, activity, service_url: nil)
    payload = activity.respond_to?(:to_h) ? activity.to_h : activity
    snapshot = Marshal.load(Marshal.dump(payload))
    @updates << [conversation_id, activity_id, snapshot, service_url]
    { "id" => activity_id }
  end

  private

  def stream_id_for(payload)
    Array(payload["entities"]).find { |entity| entity["type"] == "streaminfo" }&.fetch("streamId", nil)
  end
end

class FakeHttp
  attr_reader :posts, :responses

  def initialize(responses = {})
    @responses = responses
    @posts = []
  end

  def get(url, **)
    responses.fetch(url)
  end

  def post(url, **kwargs)
    @posts << [url, kwargs]
    responses.fetch(url)
  end
end

module JwtTestHelper
  module_function

  def b64(value)
    Base64.urlsafe_encode64(value, padding: false)
  end

  def jwk_for(rsa, kid: "test-kid")
    {
      "kid" => kid,
      "kty" => "RSA",
      "alg" => "RS256",
      "use" => "sig",
      "n" => b64(rsa.n.to_s(2)),
      "e" => b64(rsa.e.to_s(2))
    }
  end

  def token(rsa:, kid:, payload:)
    header = { "alg" => "RS256", "typ" => "JWT", "kid" => kid }
    signing_input = "#{b64(JSON.generate(header))}.#{b64(JSON.generate(payload))}"
    signature = rsa.sign(OpenSSL::Digest.new("SHA256"), signing_input)
    "#{signing_input}.#{b64(signature)}"
  end
end

def teams_payload(text: "hello", service_url: "https://smba.trafficmanager.net/teams")
  {
    "type" => "message",
    "id" => "activity-1",
    "replyToId" => "root-1",
    "serviceUrl" => service_url,
    "channelId" => "msteams",
    "from" => { "id" => "user-1", "name" => "User One", "aadObjectId" => "aad-1" },
    "recipient" => { "id" => "bot-1", "name" => "Bot" },
    "conversation" => { "id" => "conversation-1" },
    "text" => text
  }
end

def quoted_teams_payload
  teams_payload.merge(
    "entities" => [
      {
        "type" => "quotedReply",
        "quotedReply" => {
          "messageId" => "quoted-1",
          "senderId" => "user-2",
          "senderName" => "User Two",
          "preview" => "previous message"
        }
      }
    ]
  )
end

def suggested_action_submit_payload(value: { "choice" => "approve" })
  teams_payload.merge(
    "type" => "invoke",
    "name" => "suggestedActions/submit",
    "value" => value
  )
end
