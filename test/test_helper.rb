# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "rack/test"
require "json"
require "openssl"
require "base64"
require "stringio"
require "teams"

class FakeUserTokens
  attr_accessor :token
  attr_reader :sign_outs, :token_requests

  def initialize
    @token = nil
    @sign_outs = []
    @token_requests = []
  end

  def get_token(user_id:, connection_name:, channel_id: nil, code: nil)
    @token_requests << { user_id:, connection_name:, channel_id:, code: }
    unless @token
      raise Teams::HttpError.new("HTTP request failed with status 404", status: 404, headers: {}, body: "")
    end

    Teams::Api::TokenResponse.new("connectionName" => connection_name, "token" => @token)
  end

  def sign_out(user_id:, connection_name:, channel_id:)
    @sign_outs << { user_id:, connection_name:, channel_id: }
    nil
  end

  def exchange_token(user_id:, connection_name:, channel_id:, exchange_request:)
    @exchanges ||= []
    @exchanges << { user_id:, connection_name:, channel_id:, exchange_request: }
    unless @token
      raise Teams::HttpError.new("HTTP request failed with status 404", status: 404, headers: {}, body: "")
    end

    Teams::Api::TokenResponse.new("connectionName" => connection_name, "token" => @token)
  end

  def exchanges
    @exchanges ||= []
  end
end

class FakeBotSignIn
  attr_reader :states

  def initialize
    @states = []
  end

  def sign_in
    self
  end

  def get_resource(state:, **)
    @states << state
    Teams::Api::SignInUrlResponse.new(
      "signInLink" => "https://token.botframework.com/signin?state=#{state}",
      "tokenExchangeResource" => { "id" => "resource-1", "uri" => "api://botid-x/scope" },
      "tokenPostResource" => { "sasUrl" => "https://token.botframework.com/sas" }
    )
  end
end

class FakeApi
  attr_reader :service_url, :sent, :replies, :updates, :targeted_sent, :targeted_updates, :users, :bots
  attr_accessor :send_filter

  def initialize(service_url: "https://smba.trafficmanager.net/teams")
    @service_url = service_url
    @sent = []
    @replies = []
    @updates = []
    @targeted_sent = []
    @targeted_updates = []
    @users = FakeUserTokens.new
    @bots = FakeBotSignIn.new
  end

  # The app sends through api.conversations; the fake records on itself so
  # tests keep reading api.sent / api.replies / api.updates directly.
  def conversations
    self
  end

  def create_activity(conversation_id, activity, service_url: nil)
    payload = activity.respond_to?(:to_h) ? activity.to_h : activity
    snapshot = Marshal.load(Marshal.dump(payload))
    @send_filter&.call(snapshot)
    @sent << [conversation_id, snapshot, service_url]

    # Live Teams answers the stream-starting post with 201 and an id, but
    # follow-up posts that carry a streamId get 202 with an empty body.
    return nil if stream_id_for(payload)

    { "id" => "sent-#{@sent.length}" }
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

  def create_targeted_activity(conversation_id, activity, service_url: nil)
    payload = activity.respond_to?(:to_h) ? activity.to_h : activity
    snapshot = Marshal.load(Marshal.dump(payload))
    @targeted_sent << [conversation_id, snapshot, service_url]
    { "id" => "targeted-#{@targeted_sent.length}" }
  end

  def update_targeted_activity(conversation_id, activity_id, activity, service_url: nil)
    payload = activity.respond_to?(:to_h) ? activity.to_h : activity
    snapshot = Marshal.load(Marshal.dump(payload))
    @targeted_updates << [conversation_id, activity_id, snapshot, service_url]
    { "id" => activity_id }
  end

  attr_accessor :member_missing

  def get_member_by_id(conversation_id, member_id, service_url: nil)
    if @member_missing
      raise Teams::HttpError.new("HTTP request failed with status 404", status: 404, headers: {}, body: "")
    end

    Teams::Api::Account.new("id" => member_id, "name" => "Member")
  end

  def create(members: nil, tenant_id: nil, activity: nil, channel_data: nil, service_url: nil)
    created_conversations << { members:, tenant_id: }
    Teams::Api::ConversationResource.new("id" => "created-conversation-1")
  end

  def created_conversations
    @created_conversations ||= []
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
    respond(url)
  end

  def post(url, **kwargs)
    @posts << [url, kwargs]
    respond(url)
  end

  private

  # A response value may be a plain body, a proc returning one, or an
  # exception instance to raise (mirroring HttpClient raising HttpError).
  def respond(url)
    response = responses.fetch(url)
    response = response.call if response.respond_to?(:call)
    raise response if response.is_a?(Exception)

    response
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

def targeted_teams_payload(text: "hello")
  payload = teams_payload(text:)
  payload["recipient"] = payload["recipient"].merge("isTargeted" => true)
  payload["conversation"] = payload["conversation"].merge("conversationType" => "groupChat")
  payload
end

def message_update_payload(text: "edited", event_type: "editMessage")
  teams_payload(text:).merge(
    "type" => "messageUpdate",
    "channelData" => { "eventType" => event_type }
  )
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

def dialog_invoke_payload(name, data: {}, context: { "theme" => "default" })
  teams_payload.merge(
    "type" => "invoke",
    "name" => name,
    "value" => { "data" => data, "context" => context }
  )
end

def message_ext_payload(name, value)
  teams_payload.merge("type" => "invoke", "name" => name, "value" => value)
end

def suggested_action_submit_payload(value: { "choice" => "approve" })
  teams_payload.merge(
    "type" => "invoke",
    "name" => "suggestedActions/submit",
    "value" => value
  )
end
