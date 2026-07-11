# frozen_string_literal: true

require "uri"

module Teams
  module Api
    class ConversationClient
      TARGETED_PARAMS = { "isTargetedActivity" => "true" }.freeze

      attr_reader :service_url, :http

      def initialize(service_url:, http:, logger: nil)
        @service_url = service_url.sub(%r{/+\z}, "")
        @http = http
        @logger = logger
      end

      def create_activity(conversation_id, activity, service_url: nil)
        path = "/v3/conversations/#{escape(conversation_id)}/activities"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API POST #{url}")
        http.post(url, json: activity_to_h(activity))
      end

      def reply_to_activity(conversation_id, activity_id, activity, service_url: nil)
        body = activity_to_h(activity)
        body = body.merge("replyToId" => activity_id) if body.is_a?(Hash)
        path = "/v3/conversations/#{escape(conversation_id)}/activities/#{escape(activity_id)}"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API POST #{url}")
        http.post(url, json: body)
      end

      def update_activity(conversation_id, activity_id, activity, service_url: nil)
        path = "/v3/conversations/#{escape(conversation_id)}/activities/#{escape(activity_id)}"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API PUT #{url}")
        http.put(url, json: activity_to_h(activity))
      end

      def delete_activity(conversation_id, activity_id, service_url: nil)
        path = "/v3/conversations/#{escape(conversation_id)}/activities/#{escape(activity_id)}"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API DELETE #{url}")
        http.delete(url)
      end

      def create_targeted_activity(conversation_id, activity, service_url: nil)
        path = "/v3/conversations/#{escape(conversation_id)}/activities"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API POST #{url} (targeted)")
        http.post(url, json: activity_to_h(activity), params: TARGETED_PARAMS)
      end

      def update_targeted_activity(conversation_id, activity_id, activity, service_url: nil)
        path = "/v3/conversations/#{escape(conversation_id)}/activities/#{escape(activity_id)}"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API PUT #{url} (targeted)")
        http.put(url, json: activity_to_h(activity), params: TARGETED_PARAMS)
      end

      def delete_targeted_activity(conversation_id, activity_id, service_url: nil)
        path = "/v3/conversations/#{escape(conversation_id)}/activities/#{escape(activity_id)}"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API DELETE #{url} (targeted)")
        http.delete(url, params: TARGETED_PARAMS)
      end

      def add_reaction(conversation_id, activity_id, reaction_type)
        reactions.add(conversation_id, activity_id, reaction_type)
      end

      def delete_reaction(conversation_id, activity_id, reaction_type)
        reactions.delete(conversation_id, activity_id, reaction_type)
      end

      private

      def reactions
        @reactions ||= ReactionClient.new(service_url:, http:)
      end

      def activity_to_h(activity)
        case activity
        when String
          MessageActivity.new(activity).to_h
        when Hash
          Common::Hashes.deep_stringify_keys(activity)
        else
          activity.respond_to?(:to_h) ? activity.to_h : activity
        end
      end

      def absolute(path, service_url: nil)
        "#{(service_url || self.service_url).sub(%r{/+\z}, "")}#{path}"
      end

      def escape(value)
        URI.encode_www_form_component(value.to_s)
      end
    end
  end
end
