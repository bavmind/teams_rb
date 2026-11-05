# frozen_string_literal: true

module Teams
  module Api
    # Content type of an inbound uploaded-file attachment; its content is a
    # FileDownloadInfo.
    FILE_DOWNLOAD_INFO_CONTENT_TYPE = "application/vnd.microsoft.teams.file.download.info"

    # The content of a file.download.info attachment, describing an uploaded
    # file. Mirrors the TypeScript, Python, and .NET FileDownloadInfo.
    class FileDownloadInfo < Model
      # Pre-authorized, short-lived URL the file can be fetched from with a
      # plain GET (no bearer token).
      def download_url
        read("downloadUrl", "download_url")
      end

      # The OneDrive/ODSP identifier for the file, when reported.
      def unique_id
        read("uniqueId", "unique_id")
      end

      # The file extension, e.g. "pdf".
      def file_type
        read("fileType", "file_type")
      end

      # Server-assigned version tag for the file's contents, when provided.
      def etag
        read("etag")
      end
    end
  end
end
