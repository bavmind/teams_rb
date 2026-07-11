# frozen_string_literal: true

module Teams
  module Api
    class ActivityValue < Model
      # The invoke payload's data, e.g. dialog submit form values plus the
      # card action's data (dialog_id / action routing keys).
      def data
        read("data")
      end
    end
  end
end
