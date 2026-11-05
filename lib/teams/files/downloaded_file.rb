# frozen_string_literal: true

module Teams
  module Files
    # A buffered, point-in-time snapshot of a downloaded file's bytes that the
    # caller owns. Returned by IncomingFile#download; its readers never
    # re-download, so holding one is the way to read a file several ways.
    class DownloadedFile
      # bytes is a binary String; content_type is resolved from the response
      # (never empty: falls back to application/octet-stream); source_url is
      # where the bytes were actually fetched from.
      attr_reader :bytes, :content_type, :filename, :source_url

      def initialize(bytes:, content_type:, filename:, source_url:)
        @bytes = bytes
        @content_type = content_type
        @filename = filename
        @source_url = source_url
      end

      # Decodes the bytes (UTF-8 by default). No content-type check; lossy:
      # invalid bytes become U+FFFD instead of raising. Use bytes for strict or
      # binary-safe reads.
      def text(encoding = Encoding::UTF_8)
        bytes.dup.force_encoding(encoding).scrub
      end

      # Writes the buffered bytes to a local path (no re-fetch).
      def save_as(path)
        File.binwrite(path, bytes)
        nil
      end
    end
  end
end
