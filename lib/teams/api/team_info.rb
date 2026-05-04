# frozen_string_literal: true

module Teams
  module Api
    class TeamInfo < Model
      def id
        read("id")
      end

      def name
        read("name")
      end

      def team_type
        read("teamType", "team_type")
      end

      def member_count
        read("memberCount", "member_count")
      end

      def channel_count
        read("channelCount", "channel_count")
      end

      def aad_group_id
        read("aadGroupId", "aad_group_id")
      end

      def to_h
        body = raw.dup
        body["teamType"] = team_type if team_type
        body["memberCount"] = member_count if member_count
        body["channelCount"] = channel_count if channel_count
        body["aadGroupId"] = aad_group_id if aad_group_id
        body.delete("team_type")
        body.delete("member_count")
        body.delete("channel_count")
        body.delete("aad_group_id")
        body
      end
    end
  end
end
