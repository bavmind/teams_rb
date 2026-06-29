# frozen_string_literal: true

require "uri"

module Teams
  module Api
    class ReactionClient
      attr_reader :service_url, :http

      def initialize(service_url:, http:)
        @service_url = service_url.sub(%r{/+\z}, "")
        @http = http
      end

      def add(conversation_id, activity_id, reaction_type)
        http.put(path(conversation_id, activity_id, reaction_type))
      end

      def delete(conversation_id, activity_id, reaction_type)
        http.delete(path(conversation_id, activity_id, reaction_type))
      end

      private

      def path(conversation_id, activity_id, reaction_type)
        "#{service_url}/v3/conversations/#{escape(conversation_id)}/activities/#{escape(activity_id)}/reactions/#{escape(reaction_type)}"
      end

      def escape(value)
        URI.encode_www_form_component(value.to_s)
      end
    end
  end
end
