# frozen_string_literal: true

module Teams
  module Api
    class AppInfo < Model
      def id
        read("id")
      end

      def version
        read("version")
      end
    end
  end
end
