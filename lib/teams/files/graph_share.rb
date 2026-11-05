# frozen_string_literal: true

require "base64"
require "uri"

module Teams
  module Files
    # Microsoft Graph /shares addressing for drive items reached by their
    # sharing URL, like the TypeScript, Python, and .NET SDKs.
    module GraphShare
      LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1 [::1]].freeze

      module_function

      # Graph's sharing-token encoding: base64url without padding, prefixed
      # with "u!".
      def encode_sharing_url(url)
        "u!#{Base64.urlsafe_encode64(url.encode("UTF-8"), padding: false)}"
      end

      # The Graph endpoint that streams a drive item's bytes. base_url_root is
      # a host root such as https://graph.microsoft.com; the API version is
      # appended here. The request carries a bearer token, so the root must be
      # https (loopback http stays allowed for a local mock Graph).
      def drive_item_content_url(sharing_url, base_url_root = "https://graph.microsoft.com")
        unless safe_graph_root?(base_url_root)
          raise Error, "cannot fetch file bytes through Graph: the Graph host root must use https, got " \
            "#{base_url_root.inspect}. This request carries a bearer token, so a cleartext root would put it on the wire."
        end

        "#{base_url_root.chomp("/")}/v1.0/shares/#{encode_sharing_url(sharing_url)}/driveItem/content"
      end

      def safe_graph_root?(root)
        uri = URI.parse(root.to_s)
        return true if uri.scheme == "https"

        uri.scheme == "http" && LOOPBACK_HOSTS.include?(uri.host)
      rescue URI::Error
        false
      end
    end
  end
end
