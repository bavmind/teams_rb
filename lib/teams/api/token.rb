# frozen_string_literal: true

module Teams
  module Api
    class TokenResponse < Model
      def channel_id
        read("channelId", "channel_id")
      end

      def connection_name
        read("connectionName", "connection_name")
      end

      def token
        read("token")
      end

      def expiration
        read("expiration")
      end

      def properties
        read("properties")
      end
    end

    class TokenStatus < Model
      def channel_id
        read("channelId", "channel_id")
      end

      def connection_name
        read("connectionName", "connection_name")
      end

      def has_token
        read("hasToken", "has_token")
      end

      def service_provider_display_name
        read("serviceProviderDisplayName", "service_provider_display_name")
      end
    end

    class TokenExchangeResource < Model
      def id
        read("id")
      end

      def uri
        read("uri")
      end

      def provider_id
        read("providerId", "provider_id")
      end
    end

    class TokenPostResource < Model
      def sas_url
        read("sasUrl", "sas_url")
      end
    end

    class SignInUrlResponse < Model
      def sign_in_link
        read("signInLink", "sign_in_link")
      end

      def token_exchange_resource
        value = read("tokenExchangeResource", "token_exchange_resource")
        value ? TokenExchangeResource.new(value) : nil
      end

      def token_post_resource
        value = read("tokenPostResource", "token_post_resource")
        value ? TokenPostResource.new(value) : nil
      end
    end
  end
end
