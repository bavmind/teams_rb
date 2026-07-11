# frozen_string_literal: true

module Teams
  module Api
    class ActivityValue < Model
      # The invoke payload's data, e.g. dialog submit form values plus the
      # card action's data (dialog_id / action routing keys).
      def data
        read("data")
      end

      # The message extension command that fired (query/submit/fetchTask).
      def command_id
        read("commandId", "command_id")
      end

      # Message extension query parameters: [{"name" => ..., "value" => ...}].
      def parameters
        Array(read("parameters"))
      end
    end
  end
end
