# frozen_string_literal: true

module Teams
  module Api
    class CitationAppearance < Model
      ADAPTIVE_CARD_CONTENT_TYPE = "application/vnd.microsoft.card.adaptive"

      def initialize(raw = nil, name: nil, text: nil, url: nil, abstract: nil, icon: nil, keywords: nil, usage_info: nil)
        body = raw || {}
        body = body.to_h if body.respond_to?(:to_h)
        body = body.merge({
          "name" => name,
          "text" => text,
          "url" => url,
          "abstract" => abstract,
          "icon" => icon,
          "keywords" => keywords,
          "usageInfo" => usage_info
        }.compact)
        super(body)
      end

      def name
        read("name")
      end

      def text
        read("text")
      end

      def url
        read("url")
      end

      def abstract
        read("abstract")
      end

      def icon
        read("icon")
      end

      def keywords
        read("keywords")
      end

      def usage_info
        read("usageInfo", "usage_info")
      end

      def to_h
        validate!

        body = {
          "@type" => "DigitalDocument",
          "name" => name,
          "abstract" => abstract
        }
        body["text"] = text if text
        body["url"] = url if url
        body["encodingFormat"] = ADAPTIVE_CARD_CONTENT_TYPE if text && !text.empty?
        body["image"] = { "@type" => "ImageObject", "name" => icon } if icon
        body["keywords"] = keywords if keywords
        body["usageInfo"] = serialized_usage_info if usage_info
        body
      end

      private

      # Accepts an Api::SensitivityUsageInfo or a hash; @type defaults to
      # CreativeWork like the TypeScript, Python, and .NET SDKs.
      def serialized_usage_info
        info = usage_info.respond_to?(:to_h) ? usage_info.to_h : usage_info
        return info unless info.is_a?(Hash)

        { "@type" => "CreativeWork" }.merge(Common::Hashes.deep_stringify_keys(info).compact)
      end

      def validate!
        validate_required!("name", name)
        validate_required!("abstract", abstract)
      end

      def validate_required!(field, value)
        return unless value.nil?

        raise ArgumentError, "citation #{field} is required"
      end
    end
  end
end
