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

      # Creates a conversation (or returns the pre-existing one for the same
      # members). isGroup/bot/topicName are omitted: the SDKs deprecate them
      # for removal, and Python never had them.
      def create(members: nil, tenant_id: nil, activity: nil, channel_data: nil, service_url: nil)
        body = {}
        body["members"] = members.map { |member| account_to_h(member) } if members
        body["tenantId"] = tenant_id if tenant_id
        body["activity"] = activity_to_h(activity) if activity
        body["channelData"] = Common::Hashes.deep_stringify_keys(channel_data) if channel_data

        url = absolute("/v3/conversations", service_url:)
        @logger&.debug("Teams API POST #{url}")
        ConversationResource.new(http.post(url, json: body))
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

      # The backend returns objectId instead of aadObjectId on some member
      # endpoints; Api::Account reads both, so the accounts here are already
      # normalized like the other SDKs' TeamsChannelAccount.
      def get_members(conversation_id, service_url: nil)
        path = "/v3/conversations/#{escape(conversation_id)}/members"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API GET #{url}")
        Array(http.get(url)).map { |member| Account.new(member) }
      end

      def get_member_by_id(conversation_id, member_id, service_url: nil)
        path = "/v3/conversations/#{escape(conversation_id)}/members/#{escape(member_id)}"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API GET #{url}")
        Account.new(http.get(url))
      end

      def get_paged_members(conversation_id, page_size: nil, continuation_token: nil, service_url: nil)
        params = {}
        params["pageSize"] = page_size if page_size
        params["continuationToken"] = continuation_token if continuation_token

        path = "/v3/conversations/#{escape(conversation_id)}/pagedMembers"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API GET #{url}")
        PagedMembersResult.new(http.get(url, params: params.empty? ? nil : params))
      end

      def get_activity_members(conversation_id, activity_id, service_url: nil)
        path = "/v3/conversations/#{escape(conversation_id)}/activities/#{escape(activity_id)}/members"
        url = absolute(path, service_url:)
        @logger&.debug("Teams API GET #{url}")
        Array(http.get(url)).map { |member| Account.new(member) }
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

      def account_to_h(account)
        account.is_a?(Hash) ? Common::Hashes.deep_stringify_keys(account) : account.to_h
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
