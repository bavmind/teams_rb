# frozen_string_literal: true

require "uri"

module Teams
  module Files
    # Helpers for images pasted inline into a message, like the TypeScript,
    # Python, and .NET SDKs. Teams hosts them on the Bot API and describes
    # each in the message's HTML with a format hint.
    module InlineImage
      # The formats the SDK names and types. GIF is listed as .gif/image/gif
      # but Teams saves a pasted GIF as a static PNG; other formats (BMP,
      # AVIF, ...) get no extension and application/octet-stream.
      FORMATS = {
        "png" => ["png", "image/png"],
        "jpeg" => ["jpg", "image/jpeg"],
        "gif" => ["gif", "image/gif"],
        "webp" => ["webp", "image/webp"]
      }.freeze
      OCTET_STREAM = "application/octet-stream"
      AMS_IMAGE_ITEMTYPE = "http://schema.skype.com/AMSImage"
      # The path of a Bot API-hosted inline image, capturing its attachment
      # id. The id becomes part of the file name, so it is limited to
      # characters that keep path separators out.
      PATH = %r{/v3/attachments/([A-Za-z0-9_.-]+)/views/original\z}i
      IMG_TAG = /<img\b(?:[^<>"']|"[^"]*"|'[^']*')*>/i
      ATTRIBUTE = /(?<![A-Za-z0-9_-])([A-Za-z0-9_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/
      IMAGE_CONTENT_TYPE = %r{\Aimage/([A-Za-z0-9_.+-]+)}i

      Naming = Struct.new(:name, :extension, :content_type, keyword_init: true)

      module_function

      # The attachment id of an inline image from its content URL, or nil.
      def image_id(content_url)
        URI.parse(content_url).path.to_s[PATH, 1]
      rescue URI::Error
        nil
      end

      # Maps each inline image id in a message's HTML to its format hint: the
      # itemscope of an <img> whose itemtype marks it as an inline image,
      # keyed by its itemid.
      def parse_hints(html)
        html.scan(IMG_TAG).each_with_object({}) do |tag, hints|
          attributes = tag.scan(ATTRIBUTE).to_h do |name, double_quoted, single_quoted|
            [name.downcase, double_quoted || single_quoted]
          end
          id = attributes["itemid"]
          scope = attributes["itemscope"]
          next unless attributes["itemtype"] == AMS_IMAGE_ITEMTYPE && id && !id.empty? && scope && !scope.empty?

          hints[id] = scope
        end
      end

      def format_from_hint(hint)
        normalized = hint&.strip&.downcase
        return "jpeg" if normalized == "jpg"

        FORMATS.key?(normalized) ? normalized : nil
      end

      def format_from_content_type(content_type)
        format_from_hint(content_type.to_s.strip[IMAGE_CONTENT_TYPE, 1])
      end

      # The format the bytes actually are, from their magic bytes; Teams can
      # return a different format from the hint, so bytes win.
      def sniff_format(data)
        bytes = data.b
        return "png" if bytes.start_with?("\x89PNG\r\n\x1a\n".b)
        return "jpeg" if bytes.start_with?("\xFF\xD8\xFF".b)
        return "gif" if bytes.start_with?("GIF87a", "GIF89a")
        return "webp" if bytes.start_with?("RIFF") && bytes.byteslice(8, 4) == "WEBP"

        nil
      end

      def naming(base_name, format = nil)
        return Naming.new(name: base_name, extension: nil, content_type: OCTET_STREAM) unless format

        extension, content_type = FORMATS.fetch(format)
        Naming.new(name: "#{base_name}.#{extension}", extension:, content_type:)
      end
    end
  end
end
