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
      # arrive with only a content URL (agentic users); bot_api_credential the
      # Files::BotApiCredential that reads pasted inline images.
      def initialize(activity, downloader:, credential: nil, bot_api_credential: nil, logger: nil)
        @activity = activity
        @downloader = downloader
        @credential = credential
        @bot_api_credential = bot_api_credential
        @logger = logger
      end

      # The uploaded files and pasted inline images on the activity.
      # attachment_style: "file" or "inlineImage" filters by how each was
      # attached. An inline image not hosted under the activity's service URL
      # is skipped with a warning.
      def list(attachment_style: nil)
        return [] unless @activity.message?

        scope = detect_scope
        items = attachments
        hints = attachment_style == "file" ? {} : inline_image_hints(items)
        items.each_with_index.filter_map do |attachment, index|
          image_id = inline_image_id(attachment)
          # Checked before mapping, so an excluded style is never mapped and
          # never logs.
          next if attachment_style && attachment_style != (image_id ? "inlineImage" : "file")

          if image_id
            to_inline_image(attachment, image_id, index, scope, hints)
          else
            to_incoming_file(attachment, index, scope)
          end
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

      # Format hints for inline images, keyed by attachment id, from the
      # message's HTML attachments.
      def inline_image_hints(items)
        items.each_with_object({}) do |attachment, hints|
          next unless attachment["contentType"] == "text/html" && attachment["content"].is_a?(String)

          hints.merge!(InlineImage.parse_hints(attachment["content"]))
        end
      end

      # The inline image id when the attachment is an image/* at a Bot API
      # inline image path, otherwise nil.
      def inline_image_id(attachment)
        content_type = attachment["contentType"]
        content_url = attachment["contentUrl"]
        return nil unless content_type.is_a?(String) && content_type.downcase.start_with?("image/")
        return nil unless content_url.is_a?(String)

        InlineImage.image_id(content_url)
      end

      def to_inline_image(attachment, id, index, scope, hints)
        content_url = attachment["contentUrl"]
        unless Downloader.under_service_url?(content_url, @activity.service_url)
          @logger&.warn(
            "files: skipping inline image attachment at index #{index}; its location is not on the activity's service URL"
          )
          return nil
        end

        hint = hints[id]
        format = hint ? InlineImage.format_from_hint(hint) : InlineImage.format_from_content_type(attachment["contentType"])
        base_name = "image-#{id}"
        naming = InlineImage.naming(base_name, format)

        IncomingFile.new(
          name: naming.name,
          content_type: naming.content_type,
          extension: naming.extension,
          scope:,
          source: "botActivity",
          attachment_style: "inlineImage",
          content_url:,
          raw: attachment,
          inline_image_base_name: base_name,
          downloader: @downloader,
          bot_api_credential: @bot_api_credential
        )
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
