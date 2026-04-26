# frozen_string_literal: true

require "uri"

module Teams
  module Auth
    class ServiceUrlValidator
      def initialize(cloud: PUBLIC_CLOUD, additional_allowed_domains: [])
        @allowed = cloud.allowed_service_urls + additional_allowed_domains
      end

      def validate!(service_url)
        raise ServiceUrlError, "activity serviceUrl is missing" if service_url.to_s.empty?

        host = URI.parse(service_url).host
        unless allowed_host?(host)
          raise ServiceUrlError, "serviceUrl host is not allowed: #{host.inspect}"
        end

        true
      rescue URI::InvalidURIError
        raise ServiceUrlError, "serviceUrl is invalid"
      end

      private

      def allowed_host?(host)
        @allowed.any? do |allowed|
          allowed == "*" || host == allowed || host&.end_with?(".#{allowed}")
        end
      end
    end
  end
end
