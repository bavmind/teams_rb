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
        body["usageInfo"] = usage_info.to_h if usage_info && usage_info.respond_to?(:to_h)
        body["usageInfo"] = usage_info if usage_info && !usage_info.respond_to?(:to_h)
        body
      end

      private

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
