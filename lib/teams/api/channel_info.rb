# frozen_string_literal: true

module Teams
  module Api
    class ChannelInfo < Model
      def id
        read("id")
      end

      def name
        read("name")
      end

      def type
        read("type")
      end
    end
  end
end
