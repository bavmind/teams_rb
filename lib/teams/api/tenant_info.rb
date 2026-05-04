# frozen_string_literal: true

module Teams
  module Api
    class TenantInfo < Model
      def id
        read("id")
      end
    end
  end
end
