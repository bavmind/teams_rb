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

  def accessor(activity)
    Teams::Files::FilesAccessor.new(activity, downloader: @downloader)
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
