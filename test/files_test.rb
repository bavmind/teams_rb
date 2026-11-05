# frozen_string_literal: true

require_relative "test_helper"
require "socket"
require "tmpdir"

class FilesTest < Minitest::Test
  FILE_TYPE = Teams::Api::FILE_DOWNLOAD_INFO_CONTENT_TYPE
  DOWNLOAD_URL = "https://files.example.com/download/report"

  def setup
    @stubs = Faraday::Adapter::Test::Stubs.new
    @downloader = Teams::Files::Downloader.new(connection: Faraday.new { |f| f.adapter(:test, @stubs) })
  end

  def test_list_maps_uploaded_files_and_skips_other_attachments
    raw_file = file_attachment
    files = accessor(activity([card_attachment, raw_file, { "contentType" => "text/html", "content" => "<p>hi</p>" }])).list

    assert_equal 1, files.length
    file = files.first
    assert_equal "report.pdf", file.name
    assert_equal "personal", file.scope
    assert_equal "botActivity", file.source
    assert_equal "file", file.attachment_style
    assert_equal "unique-1", file.unique_id
    assert_equal "pdf", file.extension
    assert_equal "https://contoso.sharepoint.com/report.pdf", file.content_url
    assert_nil file.content_type
    assert_equal raw_file, file.raw
  end

  def test_list_skips_malformed_entries_without_raising
    attachments = [
      file_attachment(name: nil),
      file_attachment(download_url: nil, content_url: nil),
      { "contentType" => FILE_TYPE, "name" => "x.txt", "content" => "not-a-hash" },
      "not-an-attachment",
      file_attachment(name: "kept.txt", extra: { "uniqueId" => 42 })
    ]

    files = accessor(activity(attachments)).list

    assert_equal ["kept.txt"], files.map(&:name)
    assert_nil files.first.unique_id
  end

  def test_list_is_empty_for_non_message_activities
    assert_empty accessor(activity([file_attachment], type: "invoke")).list
    assert_nil accessor(activity([], type: "message")).first
  end

  def test_first_returns_the_first_file
    files = accessor(activity([file_attachment(name: "a.txt"), file_attachment(name: "b.txt")]))

    assert_equal "a.txt", files.first.name
  end

  def test_download_is_a_plain_get_without_authorization
    seen_headers = nil
    @stubs.get(DOWNLOAD_URL) do |env|
      seen_headers = env.request_headers
      [200, { "Content-Type" => "application/pdf" }, "%PDF-bytes"]
    end

    downloaded = accessor(activity([file_attachment])).first.download

    refute seen_headers.key?("Authorization")
    assert_equal "%PDF-bytes", downloaded.bytes
    assert_equal Encoding::BINARY, downloaded.bytes.encoding
    assert_equal "application/pdf", downloaded.content_type
    assert_equal "report.pdf", downloaded.filename
    assert_equal DOWNLOAD_URL, downloaded.source_url
  end

  def test_download_falls_back_to_octet_stream_content_type
    @stubs.get(DOWNLOAD_URL) { [200, {}, "bytes"] }

    assert_equal "application/octet-stream", accessor(activity([file_attachment])).first.download.content_type
  end

  def test_download_follows_https_redirects
    @stubs.get(DOWNLOAD_URL) { [302, { "Location" => "https://storage.example.net/blob" }, ""] }
    @stubs.get("https://storage.example.net/blob") { [200, { "Content-Type" => "text/plain" }, "redirected"] }

    assert_equal "redirected", accessor(activity([file_attachment])).first.download.bytes
  end

  def test_download_refuses_a_redirect_to_plaintext
    @stubs.get(DOWNLOAD_URL) { [302, { "Location" => "http://storage.example.net/blob" }, ""] }

    error = assert_raises(Teams::Error) { accessor(activity([file_attachment])).first.download }
    assert_includes error.message, "redirect destination must use https"
  end

  def test_expired_url_raises_first_fetch_then_reread
    file = accessor(activity([file_attachment])).first
    @stubs.get(DOWNLOAD_URL) { [403, {}, "expired"] }
    error = assert_raises(Teams::FileUrlExpiredError) { file.download }
    assert_equal "first_fetch", error.reason
    assert_kind_of Teams::FileError, error

    file = accessor(activity([file_attachment])).first
    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.get(DOWNLOAD_URL) { [200, {}, "ok"] }
    stubs.get(DOWNLOAD_URL) { [401, {}, "expired"] }
    file.instance_variable_set(:@downloader, Teams::Files::Downloader.new(connection: Faraday.new { |f| f.adapter(:test, stubs) }))
    file.download
    assert_equal "reread", assert_raises(Teams::FileUrlExpiredError) { file.download }.reason
  end

  def test_other_download_failures_raise_a_plain_error
    @stubs.get(DOWNLOAD_URL) { [500, {}, "boom"] }

    error = assert_raises(Teams::Error) { accessor(activity([file_attachment])).first.download }
    refute_kind_of Teams::FileError, error
    assert_includes error.message, "500"
  end

  def test_download_requires_https_download_url
    file = accessor(activity([file_attachment(download_url: "http://files.example.com/x")])).first

    assert_includes assert_raises(Teams::Error) { file.download }.message, "must use https"
  end

  def test_group_chat_file_with_download_url_is_listed_but_not_downloadable
    file = accessor(activity([file_attachment], conversation_type: "groupChat")).first

    assert_equal "groupChat", file.scope
    error = assert_raises(Teams::FileScopeNotSupportedError) { file.download }
    assert_equal "groupChat", error.scope
  end

  def test_text_is_lossy_stream_yields_chunks_and_save_as_writes_the_file
    @stubs.get(DOWNLOAD_URL) { [200, {}, "caf\xC3\xA9 \xFF".b] }
    file = accessor(activity([file_attachment])).first

    assert_equal "café �", file.text
    assert_equal ["caf\xC3\xA9 \xFF".b], file.stream.to_a

    Dir.mktmpdir do |dir|
      path = File.join(dir, "report.pdf")
      file.save_as(path)
      assert_equal "caf\xC3\xA9 \xFF".b, File.binread(path)

      downloaded = file.download
      copy = File.join(dir, "copy.pdf")
      downloaded.save_as(copy)
      assert_equal downloaded.bytes, File.binread(copy)
    end
  end

  def test_failed_save_as_does_not_create_the_file
    @stubs.get(DOWNLOAD_URL) { [403, {}, ""] }
    file = accessor(activity([file_attachment])).first

    Dir.mktmpdir do |dir|
      path = File.join(dir, "report.pdf")
      assert_raises(Teams::FileUrlExpiredError) { file.save_as(path) }
      refute File.exist?(path)
    end
  end

  # The test adapter hands bodies over whole; this drives the real Net::HTTP
  # adapter so success bodies stream through on_data while error bodies are
  # captured (capped) instead of reaching the consumer.
  def test_net_http_streams_success_bodies_and_captures_error_bodies
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    responses = [
      "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n",
      "HTTP/1.1 403 Forbidden\r\nContent-Length: 6\r\n\r\ndenied"
    ]
    thread = Thread.new do
      responses.each do |raw|
        client = server.accept
        client.gets("\r\n\r\n")
        client.write(raw)
        client.close
      end
    end
    downloader = Teams::Files::Downloader.new(connection: Faraday.new { |f| f.adapter(:net_http) })

    chunks = []
    ok = downloader.send(:perform_get, "http://127.0.0.1:#{port}/ok", {}) { |chunk| chunks << chunk }
    denied_chunks = []
    denied = downloader.send(:perform_get, "http://127.0.0.1:#{port}/denied", {}) { |chunk| denied_chunks << chunk }

    assert_equal 200, ok.status
    assert_equal "hello world", chunks.join
    assert_equal 403, denied.status
    assert_empty denied_chunks
    assert_equal "denied", denied.error_body
  ensure
    thread&.join(5)
    server&.close
  end

  SHARING_URL = "https://contoso.sharepoint.com/sites/x/Shared Documents/report.pdf"
  GRAPH_CONTENT_URL = "https://graph.microsoft.com/v1.0/shares/" \
    "u!aHR0cHM6Ly9jb250b3NvLnNoYXJlcG9pbnQuY29tL3NpdGVzL3gvU2hhcmVkIERvY3VtZW50cy9yZXBvcnQucGRm/driveItem/content"

  def test_encode_sharing_url_matches_graph_encoding
    assert_equal GRAPH_CONTENT_URL, Teams::Files::GraphShare.drive_item_content_url(SHARING_URL)
    assert_equal "http://localhost:8080/v1.0/shares/u!eA/driveItem/content",
      Teams::Files::GraphShare.drive_item_content_url("x", "http://localhost:8080/")
    assert_raises(Teams::Error) { Teams::Files::GraphShare.drive_item_content_url("x", "http://graph.example.com") }
  end

  def test_agentic_personal_file_reads_through_graph_as_the_agent
    seen = nil
    @stubs.get(GRAPH_CONTENT_URL) do |env|
      seen = env.request_headers["Authorization"]
      [200, { "Content-Type" => "application/pdf" }, "graph-bytes"]
    end

    file = accessor(activity([agentic_file_attachment]), credential: graph_credential).first
    downloaded = file.download

    assert_equal "Bearer #{files_token}", seen
    assert_equal "graph-bytes", downloaded.bytes
    assert_equal GRAPH_CONTENT_URL, downloaded.source_url
  end

  def test_group_chat_and_channel_files_open_only_for_agentic_users
    %w[groupChat channel].each do |scope|
      agent_files = accessor(activity([agentic_file_attachment], conversation_type: scope), credential: graph_credential).list
      app_files = accessor(activity([agentic_file_attachment], conversation_type: scope), credential: graph_credential(actor: "app")).list

      assert_equal 1, agent_files.length, scope
      assert_empty app_files, scope
    end

    @stubs.get(GRAPH_CONTENT_URL) { [200, {}, "channel-bytes"] }
    file = accessor(activity([agentic_file_attachment], conversation_type: "channel"), credential: graph_credential).first
    assert_equal "channel-bytes", file.download.bytes
  end

  def test_download_url_outside_personal_keeps_the_scope_error_for_agents
    file = accessor(activity([file_attachment], conversation_type: "groupChat"), credential: graph_credential).first

    assert_raises(Teams::FileScopeNotSupportedError) { file.download }
  end

  def test_graph_refusal_raises_file_access_error_with_service_details
    @stubs.get(GRAPH_CONTENT_URL) do
      [403, { "Content-Type" => "application/json" }, JSON.generate("error" => { "code" => "accessDenied", "message" => "Not shared" })]
    end

    error = assert_raises(Teams::FileAccessError) do
      accessor(activity([agentic_file_attachment]), credential: graph_credential).first.download
    end
    assert_equal 403, error.status
    assert_equal "agentic_user", error.actor
    assert_equal "accessDenied: Not shared", error.details
    assert_includes error.message, "the agentic user"
  end

  def test_unexpected_graph_status_carries_service_text
    @stubs.get(GRAPH_CONTENT_URL) { [503, {}, "<html> busy </html>"] }

    error = assert_raises(Teams::Error) do
      accessor(activity([agentic_file_attachment]), credential: graph_credential).first.download
    end
    refute_kind_of Teams::FileError, error
    assert_includes error.message, "503"
    assert_includes error.message, "<html> busy </html>"
  end

  def test_missing_or_unusable_graph_credentials_fail_before_any_request
    file = ->(credential) { accessor(activity([agentic_file_attachment]), credential:).first }

    error = assert_raises(Teams::FileCredentialError) { file.call(graph_credential(token: -> {})).download }
    assert_equal "agentic_user", error.actor

    error = assert_raises(Teams::FileCredentialError) do
      file.call(graph_credential(token: -> { raise Teams::Error, "tenant unknown" })).download
    end
    assert_equal "tenant unknown", error.cause_detail

    error = assert_raises(Teams::FileCredentialError) do
      file.call(graph_credential(token: -> { jwt_with("scp" => "Mail.Send") })).download
    end
    assert_includes error.message, "inheritable permissions"
  end

  def test_undecodable_token_proceeds_to_graph
    @stubs.get(GRAPH_CONTENT_URL) { [200, {}, "ok"] }

    file = accessor(activity([agentic_file_attachment]), credential: graph_credential(token: -> { "opaque-token" })).first

    assert_equal "ok", file.download.bytes
  end

  def test_graph_redirect_to_another_origin_drops_authorization
    seen = :unset
    @stubs.get(GRAPH_CONTENT_URL) { [302, { "Location" => "https://contoso-my.sharepoint.com/download.aspx" }, ""] }
    @stubs.get("https://contoso-my.sharepoint.com/download.aspx") do |env|
      seen = env.request_headers["Authorization"]
      [200, {}, "bytes"]
    end

    accessor(activity([agentic_file_attachment]), credential: graph_credential).first.download

    assert_nil seen
  end

  def test_app_selects_the_agentic_identity_for_file_reads
    app = Teams::App.new(api: FakeApi.new, dangerously_allow_unauthenticated_requests: true, logger: Logger.new(nil))
    recorded = []
    fake_tokens = Object.new
    fake_tokens.define_singleton_method(:agentic_user_token) { |scope, **ids| recorded << [scope, ids]; "agent-token" }
    fake_tokens.define_singleton_method(:token_for) { |scope, tenant| recorded << [scope, tenant]; "app-token" }
    fake_tokens.define_singleton_method(:credentials) { nil }
    app.instance_variable_set(:@token_manager, fake_tokens)
    identity = Teams::Api::AgenticIdentity.new(agentic_app_blueprint_id: "bp", agentic_app_id: "app-1", agentic_user_id: "user-1")
    inbound = activity([])

    agent = app.send(:files_credential, inbound, identity)
    plain = app.send(:files_credential, inbound, nil)

    assert_equal "agentic_user", agent.actor
    assert_equal "agent-token", agent.token.call
    assert_equal "app", plain.actor
    assert_equal "app-token", plain.token.call
    assert_equal "https://graph.microsoft.com", agent.base_url_root
    assert_equal [
      ["https://graph.microsoft.com/.default", { agentic_app_id: "app-1", agentic_user_id: "user-1", tenant_id: "tenant-1" }],
      ["https://graph.microsoft.com/.default", "tenant-1"]
    ], recorded
  end

  IMAGE_ID = "0-wus-d1-0123abcd"
  IMAGE_URL = "https://smba.trafficmanager.net/amer/v3/attachments/#{IMAGE_ID}/views/original"

  def test_inline_images_are_listed_with_hint_naming
    files = accessor(activity([html_attachment(IMAGE_ID => "png"), inline_image_attachment])).list

    assert_equal 1, files.length
    image = files.first
    assert_equal "image-#{IMAGE_ID}.png", image.name
    assert_equal "png", image.extension
    assert_equal "image/png", image.content_type
    assert_equal "inlineImage", image.attachment_style
    assert_equal IMAGE_URL, image.content_url
    assert_equal inline_image_attachment, image.raw
  end

  def test_inline_image_format_falls_back_to_content_type_and_unknown_formats_stay_untyped
    from_type = accessor(activity([inline_image_attachment(content_type: "image/jpeg")])).first
    unknown = accessor(activity([html_attachment(IMAGE_ID => "bmp"), inline_image_attachment(content_type: "image/jpeg")])).first

    assert_equal ["image-#{IMAGE_ID}.jpg", "image/jpeg"], [from_type.name, from_type.content_type]
    assert_equal ["image-#{IMAGE_ID}", nil, "application/octet-stream"], [unknown.name, unknown.extension, unknown.content_type]
  end

  def test_attachment_style_filters_files_and_inline_images
    files = accessor(activity([file_attachment, inline_image_attachment]))

    assert_equal ["file", "inlineImage"], files.list.map(&:attachment_style)
    assert_equal ["report.pdf"], files.list(attachment_style: "file").map(&:name)
    assert_equal ["inlineImage"], files.list(attachment_style: "inlineImage").map(&:attachment_style)
    assert_equal "inlineImage", files.first(attachment_style: "inlineImage").attachment_style
  end

  def test_inline_images_off_the_service_url_are_skipped
    elsewhere = inline_image_attachment(content_url: "https://evil.example.com/v3/attachments/#{IMAGE_ID}/views/original")
    climbing = inline_image_attachment(content_url: "https://smba.trafficmanager.net/amer/../emea/v3/attachments/#{IMAGE_ID}/views/original")

    assert_empty accessor(activity([elsewhere, climbing])).list
  end

  def test_under_service_url_resolves_dot_segments_and_requires_the_same_https_origin
    base = "https://smba.trafficmanager.net/amer/"
    check = ->(url, service_url = base) { Teams::Files::Downloader.under_service_url?(url, service_url) }

    assert check.call("https://smba.trafficmanager.net/amer/v3/attachments/x/views/original")
    assert check.call("https://SMBA.trafficmanager.net/amer/./v3/x", "https://smba.trafficmanager.net/amer")
    assert check.call("https://smba.trafficmanager.net/a%2fb/v3/x", "https://smba.trafficmanager.net/a%2Fb")
    refute check.call("https://smba.trafficmanager.net/americas/v3/x", "https://smba.trafficmanager.net/amer")
    refute check.call("https://smba.trafficmanager.net/amer/../emea/v3/x")
    refute check.call("https://smba.trafficmanager.net/amer/%2E%2e/emea/v3/x")
    refute check.call("https://other.example.com/amer/v3/x")
    refute check.call("https://smba.trafficmanager.net:8443/amer/v3/x")
    refute check.call("http://smba.trafficmanager.net/amer/v3/x", "http://smba.trafficmanager.net/amer/")
    refute check.call("https://smba.trafficmanager.net/amer/v3/x", nil)
  end

  def test_inline_image_download_uses_the_turn_token_and_sniffed_format
    seen = nil
    @stubs.get(IMAGE_URL) do |env|
      seen = env.request_headers["Authorization"]
      [200, { "Content-Type" => "image/gif" }, "\x89PNG\r\n\x1a\nrest".b]
    end

    image = accessor(activity([html_attachment(IMAGE_ID => "gif"), inline_image_attachment]), bot_api_credential: bot_api_credential).first
    downloaded = image.download

    assert_equal "image-#{IMAGE_ID}.gif", image.name
    assert_equal "Bearer bot-token", seen
    assert_equal "image-#{IMAGE_ID}.png", downloaded.filename
    assert_equal "image/png", downloaded.content_type
  end

  def test_unrecognized_inline_image_bytes_keep_the_listing_type
    @stubs.get(IMAGE_URL) { [200, { "Content-Type" => "image/bmp" }, "BMbytes"] }

    image = accessor(activity([html_attachment(IMAGE_ID => "png"), inline_image_attachment]), bot_api_credential: bot_api_credential).first

    assert_equal ["image-#{IMAGE_ID}.png", "image/png"], image.download.then { |d| [d.filename, d.content_type] }
  end

  def test_inline_image_refusals_raise_typed_errors
    image = -> { accessor(activity([inline_image_attachment]), bot_api_credential: bot_api_credential).first }

    @stubs.get(IMAGE_URL) do
      [415, {}, JSON.generate("error" => { "code" => "TransformationFailed", "message" => "Cannot convert" })]
    end
    error = assert_raises(Teams::InlineImageTransformationError) { image.call.download }
    assert_equal [415, "TransformationFailed", "app"], [error.status, error.code, error.actor]
    assert_equal "TransformationFailed: Cannot convert", error.details

    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.get(IMAGE_URL) { [403, {}, ""] }
    @downloader = Teams::Files::Downloader.new(connection: Faraday.new { |f| f.adapter(:test, stubs) })
    error = assert_raises(Teams::InlineImageAccessError) { image.call.download }
    assert_equal 403, error.status
    assert_includes error.message, "not allowed to read the image"
  end

  def test_inline_image_download_requires_a_token_and_the_service_url
    blank = accessor(activity([inline_image_attachment]), bot_api_credential: bot_api_credential(token: -> { "  " })).first
    assert_includes assert_raises(Teams::Error) { blank.download }.message, "no Bot API token"

    moved = accessor(activity([inline_image_attachment]),
      bot_api_credential: bot_api_credential(service_url: "https://smba.trafficmanager.net/emea/")).first
    assert_includes assert_raises(Teams::Error) { moved.download }.message, "not under the activity's service URL"
  end

  def test_app_resolves_the_turn_api_token_for_inline_images
    app = Teams::App.new(api: FakeApi.new, dangerously_allow_unauthenticated_requests: true, logger: Logger.new(nil))
    turn_api = Teams::Api::Client.new(service_url: "https://smba.trafficmanager.net/amer/",
      http: Teams::Common::HttpClient.new(token: -> { "turn-token" }))

    credential = app.send(:files_bot_api_credential, activity([]), nil, turn_api)

    assert_equal ["app", "https://smba.trafficmanager.net/amer/", "turn-token"],
      [credential.actor, credential.service_url, credential.token.call]
  end

  def test_ctx_files_lists_the_inbound_activity_files
    app = Teams::App.new(api: FakeApi.new, dangerously_allow_unauthenticated_requests: true, logger: Logger.new(nil))
    inbound = activity([file_attachment])
    ctx = Teams::ActivityContext.new(
      app:, activity: inbound, conversation_reference: Teams::Api::ConversationReference.from_activity(inbound)
    )

    assert_same ctx.files, ctx.files
    assert_equal ["report.pdf"], ctx.files.list.map(&:name)
  end

  private

  def accessor(activity, credential: nil, bot_api_credential: nil)
    Teams::Files::FilesAccessor.new(activity, downloader: @downloader, credential:, bot_api_credential:)
  end

  def bot_api_credential(token: -> { "bot-token" }, service_url: "https://smba.trafficmanager.net/amer/")
    Teams::Files::BotApiCredential.new(actor: "app", token:, service_url:)
  end

  def inline_image_attachment(content_type: "image/*", content_url: IMAGE_URL)
    { "contentType" => content_type, "contentUrl" => content_url }
  end

  def html_attachment(hints)
    images = hints.map do |id, scope|
      %(<img src="#{IMAGE_URL}" itemscope="#{scope}" itemtype="http://schema.skype.com/AMSImage" itemid="#{id}" alt="image">)
    end
    { "contentType" => "text/html", "content" => "<p>look #{images.join}</p>" }
  end

  def graph_credential(actor: "agentic_user", token: -> { files_token })
    Teams::Files::GraphCredential.new(actor:, token:, base_url_root: "https://graph.microsoft.com")
  end

  def files_token
    jwt_with("scp" => "Files.Read.All User.Read")
  end

  def jwt_with(claims)
    encode = ->(hash) { Base64.urlsafe_encode64(JSON.generate(hash), padding: false) }
    "#{encode.call("alg" => "none")}.#{encode.call(claims)}.signature"
  end

  # The agentic user shape: a content URL and content without downloadUrl.
  def agentic_file_attachment
    { "contentType" => FILE_TYPE, "name" => "report.pdf", "contentUrl" => SHARING_URL,
      "content" => { "uniqueId" => "unique-1", "fileType" => "pdf" } }
  end

  def activity(attachments, type: "message", conversation_type: "personal")
    Teams::Activity.new(
      "type" => type,
      "id" => "1772129782775",
      "serviceUrl" => "https://smba.trafficmanager.net/amer/",
      "from" => { "id" => "user-1" },
      "recipient" => { "id" => "bot-1" },
      "conversation" => { "id" => "conversation-1", "conversationType" => conversation_type, "tenantId" => "tenant-1" },
      "attachments" => attachments
    )
  end

  def file_attachment(name: "report.pdf", download_url: DOWNLOAD_URL, content_url: "https://contoso.sharepoint.com/report.pdf", extra: {})
    content = { "downloadUrl" => download_url, "uniqueId" => "unique-1", "fileType" => "pdf" }.compact.merge(extra)
    { "contentType" => FILE_TYPE, "name" => name, "contentUrl" => content_url, "content" => content }.compact
  end

  def card_attachment
    { "contentType" => "application/vnd.microsoft.card.adaptive", "content" => { "type" => "AdaptiveCard" } }
  end
end
