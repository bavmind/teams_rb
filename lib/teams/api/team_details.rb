# frozen_string_literal: true

module Teams
  module Api
    class TeamDetails < Model
      def id
        read("id")
      end

      def name
        read("name")
      end

      # "standard", "sharedChannel", or "privateChannel".
      def type
        read("type")
      end

      def aad_group_id
        read("aadGroupId", "aad_group_id")
      end

      def channel_count
        read("channelCount", "channel_count")
      end

      def member_count
        read("memberCount", "member_count")
      end

      def tenant_id
        read("tenantId", "tenant_id")
      end
    end
  end
end
