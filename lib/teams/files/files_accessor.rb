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
      # credential is the turn's Files::GraphCredential, used for files that
      # arrive with only a content URL (agentic users).
      def initialize(activity, downloader:, credential: nil, logger: nil)
        @activity = activity
        @downloader = downloader
        @credential = credential
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
        download_url = string_or_nil(content&.download_url)
        content_url = string_or_nil(attachment["contentUrl"])
        name = string_or_nil(attachment["name"])

        # A download URL is fetched directly. A content URL without one is the
        # agentic user shape (content that parsed and declares no downloadUrl
        # at all) and resolves through Graph where the route is open; a
        # broken attachment is never spent on a Graph credential.
        agentic_shape = content && !attachment["content"].key?("downloadUrl")
        graph_fetchable = agentic_shape && content_url &&
          Downloader.graph_route_open?(scope, @credential&.actor)

        if name.nil? || !(download_url || graph_fetchable)
          if name.nil? || !(download_url || content_url)
            missing = name.nil? ? "name" : "a download or content URL"
            @logger&.warn("files: skipping file.download.info attachment at index #{index}; missing #{missing}")
          else
            @logger&.debug(
              "files: skipping file.download.info attachment at index #{index}; " \
              "'#{scope}' scope files are not fetchable yet"
            )
          end
          return nil
        end

        IncomingFile.new(
          name:,
          scope:,
          source: "botActivity",
          attachment_style: "file",
          unique_id: content&.unique_id,
          extension: content&.file_type,
          content_url:,
          raw: attachment,
          download_url:,
          downloader: @downloader,
          credential: @credential
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
