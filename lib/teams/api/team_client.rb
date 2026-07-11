# frozen_string_literal: true

require "uri"

module Teams
  module Api
    class TeamClient
      attr_reader :service_url, :http

      def initialize(service_url:, http:, logger: nil)
        @service_url = service_url.sub(%r{/+\z}, "")
        @http = http
        @logger = logger
      end

      def get_by_id(team_id, service_url: nil)
        path = "/v3/teams/#{escape(team_id)}"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API GET #{url}")
        TeamDetails.new(http.get(url))
      end

      # Returns the team's channels; the service wraps them in a
      # "conversations" envelope, which all the SDKs unwrap.
      def get_conversations(team_id, service_url: nil)
        path = "/v3/teams/#{escape(team_id)}/conversations"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API GET #{url}")
        response = http.get(url)
        conversations = response.is_a?(Hash) ? Array(response["conversations"]) : []
        conversations.map { |channel| ChannelInfo.new(channel) }
      end

      private

      def absolute(path, service_url: nil)
        "#{(service_url || self.service_url).sub(%r{/+\z}, "")}#{path}"
      end

      def escape(value)
        URI.encode_www_form_component(value.to_s)
      end
    end
  end
end
