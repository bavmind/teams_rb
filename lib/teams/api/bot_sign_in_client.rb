# frozen_string_literal: true

require "uri"

module Teams
  module Api
    # Bot sign-in resources from the Bot Framework token service, used to
    # build OAuth cards. Exposed as api.bots.sign_in, following .NET's
    # non-deprecated Bots client (TypeScript/Python deprecate their bot
    # client but still call sign-in through it internally).
    class BotSignInClient
      attr_reader :oauth_url, :http

      def initialize(oauth_url:, http:, logger: nil)
        @oauth_url = oauth_url.sub(%r{/+\z}, "")
        @http = http
        @logger = logger
      end

      # Returns the sign-in URL as a plain string.
      def get_url(state:, code_challenge: nil, emulator_url: nil, final_redirect: nil)
        url = endpoint("api/botsignin/GetSignInUrl", state:, code_challenge:, emulator_url:, final_redirect:)
        @logger&.debug("Teams API GET #{url}")
        http.get(url)
      end

      def get_resource(state:, code_challenge: nil, emulator_url: nil, final_redirect: nil)
        url = endpoint("api/botsignin/GetSignInResource", state:, code_challenge:, emulator_url:, final_redirect:)
        @logger&.debug("Teams API GET #{url}")
        SignInUrlResponse.new(http.get(url))
      end

      private

      def endpoint(path, state:, code_challenge:, emulator_url:, final_redirect:)
        params = {
          "state" => state,
          "codeChallenge" => code_challenge,
          "emulatorUrl" => emulator_url,
          "finalRedirect" => final_redirect
        }.compact
        "#{oauth_url}/#{path}?#{URI.encode_www_form(params)}"
      end
    end

    class BotClient
      attr_reader :sign_in

      def initialize(oauth_url:, http:, logger: nil)
        @sign_in = BotSignInClient.new(oauth_url:, http:, logger:)
      end
    end
  end
end
