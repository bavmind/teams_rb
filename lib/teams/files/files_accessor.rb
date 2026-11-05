# frozen_string_literal: true

module Teams
  module Files
    # The uploaded files on the current inbound activity, exposed as
    # ctx.files: a filter over the raw activity attachments, mirroring the
    # TypeScript, Python, and .NET FilesAccessor.
    #
    # Uploaded files arrive as file.download.info attachments carrying file
    # metadata, not bytes. Each becomes an IncomingFile; everything else
    # (cards, mentions, other content) and malformed file entries are
    # skipped, never raised. Listing makes no network requests. What matters
    # is how the content arrived, not its MIME type, so any file type sent as
    # an uploaded file is listed. The original attachment stays on
    # IncomingFile#raw.
    class FilesAccessor
      def initialize(activity, downloader:, logger: nil)
        @activity = activity
        @downloader = downloader
        @logger = logger
      end

      # The files on the activity. attachment_style: "file" filters by how a
      # file was attached.
      def list(attachment_style: nil)
        return [] unless @activity.message?
        return [] if attachment_style && attachment_style != "file"

        scope = detect_scope
        attachments.each_with_index.filter_map do |attachment, index|
          to_incoming_file(attachment, index, scope)
        end
      end

      # The first listed file, or nil.
      def first(attachment_style: nil)
        list(attachment_style:).first
      end

      private

      def attachments
        Array(@activity.raw["attachments"]).select { |attachment| attachment.is_a?(Hash) }
      end

      def detect_scope
        @activity.conversation&.conversation_type || "personal"
      end

      def to_incoming_file(attachment, index, scope)
        return nil unless attachment["contentType"] == Api::FILE_DOWNLOAD_INFO_CONTENT_TYPE

        content = coerce_content(attachment["content"])
        download_url = content&.download_url
        content_url = string_or_nil(attachment["contentUrl"])
        name = string_or_nil(attachment["name"])

        if download_url.nil? || name.nil?
          missing = name.nil? ? "name" : "a download URL"
          @logger&.warn("files: skipping file.download.info attachment at index #{index}; missing #{missing}")
          return nil
        end

        IncomingFile.new(
          name:,
          scope:,
          source: "botActivity",
          attachment_style: "file",
          unique_id: content.unique_id,
          extension: content.file_type,
          content_url:,
          raw: attachment,
          download_url:,
          downloader: @downloader
        )
      end

      # Wrong-typed fields are dropped one at a time rather than rejecting the
      # whole object, like the Python SDK: unique_id and file_type are
      # metadata, and failing on one must not drop a usable download URL.
      def coerce_content(content)
        return nil unless content.is_a?(Hash)

        Api::FileDownloadInfo.new(content.select { |_key, value| value.nil? || value.is_a?(String) })
      end

      def string_or_nil(value)
        value.is_a?(String) && !value.empty? ? value : nil
      end
    end
  end
end
