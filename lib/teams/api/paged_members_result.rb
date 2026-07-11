# frozen_string_literal: true

module Teams
  module Api
    class PagedMembersResult < Model
      def members
        Array(read("members")).map { |member| Account.new(member) }
      end

      # Token to fetch the next page of members; nil on the last page.
      def continuation_token
        read("continuationToken", "continuation_token")
      end
    end
  end
end
