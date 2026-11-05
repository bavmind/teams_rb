# frozen_string_literal: true

module Teams
  module Files
    # A lazy handle to a file attached to the current inbound activity,
    # mirroring the TypeScript, Python, and .NET IncomingFile.
    #
    # Nothing is downloaded until a byte method is called, and no bytes are
    # memoized: each of stream/download/text/save_as fetches afresh. For a
    # personal file that re-fetch is bounded by the short-lived download URL;
    # to read the same file several ways, call download once and reuse the
    # returned DownloadedFile.
    class IncomingFile
      # name: display name including extension when known.
      # scope: the conversation type the file arrived in ("personal", ...).
      # source: where the SDK found the file; only "botActivity" today.
      # attachment_style: "file" (sent as a file attachment).
      # unique_id: the OneDrive/ODSP identifier when reported (for
      #   correlation and logging, not retrieval).
      # content_type: the file's MIME type when the source provides one;
      #   always nil for file attachments, which carry only the extension.
      #   DownloadedFile#content_type is resolved from the download response.
      # extension: extension without the dot, from the platform's fileType.
      # content_url: browsable link to the file in OneDrive/SharePoint, as
      #   sent on the attachment; not fetchable for bytes.
      # raw: the original attachment hash.
      attr_reader :name, :scope, :source, :attachment_style, :unique_id, :content_type, :extension,
        :content_url, :raw

      def initialize(name:, scope:, source:, downloader:, unique_id: nil, content_type: nil, extension: nil,
        attachment_style: "file", content_url: nil, raw: nil, download_url: nil)
        @name = name
        @scope = scope
        @source = source
        @unique_id = unique_id
        @content_type = content_type
        @extension = extension
        @attachment_style = attachment_style
        @content_url = content_url
        @raw = raw
        @download_url = download_url
        @downloader = downloader
        @prior_fetch_succeeded = false
      end

      # Yields the response body chunks as they arrive, single-consumption and
      # not buffered. Returns an Enumerator without a block.
      def stream(&block)
        return enum_for(:stream) unless block

        fetch(&block)
        nil
      end

      # Fetches the whole file into a DownloadedFile snapshot. Not memoized:
      # calling again re-fetches.
      def download
        data = +"".b
        opened = fetch { |chunk| data << chunk }
        DownloadedFile.new(bytes: data, content_type: opened.content_type, filename: name,
          source_url: opened.source_url)
      end

      # download, then decode (UTF-8 by default, lossy). Re-fetches each call.
      def text(encoding = Encoding::UTF_8)
        download.text(encoding)
      end

      # Streams the bytes straight to a local path without buffering the
      # file in memory. The file is only created once the fetch succeeds.
      def save_as(path)
        file = nil
        fetch { |chunk| (file ||= File.open(path, "wb")).write(chunk) }
        File.binwrite(path, "") unless file
        nil
      ensure
        file&.close
      end

      private

      def fetch(&on_chunk)
        opened = @downloader.fetch(target, prior_fetch_succeeded: @prior_fetch_succeeded, &on_chunk)
        @prior_fetch_succeeded = true
        opened
      end

      def target
        FetchTarget.new(
          scope:,
          download_url: @download_url,
          content_url:,
          content_type:,
          attachment_style:
        )
      end
    end
  end
end
