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

      # Meeting start/end event fields. Teams sends these PascalCase on the
      # wire (Id, JoinUrl, Title, MeetingType, StartTime, EndTime).
      def id
        read("Id", "id")
      end

      def title
        read("Title", "title")
      end

      def meeting_type
        read("MeetingType", "meetingType", "meeting_type")
      end

      def join_url
        read("JoinUrl", "joinUrl", "join_url")
      end

      def start_time
        read("StartTime", "startTime", "start_time")
      end

      def end_time
        read("EndTime", "endTime", "end_time")
      end

      # application/search invoke fields (Adaptive Card dynamic typeahead
      # Input.ChoiceSet queries via choices.data / Data.Query).
      def query_text
        read("queryText", "query_text")
      end

      # Pagination options; skip and top read from the nested wrapper.
      def query_options
        value = read("queryOptions", "query_options")
        value.is_a?(Hash) ? ActivityValue.new(value) : value
      end

      def kind
        read("kind")
      end

      # The Data.Query dataset id authored on the Adaptive Card.
      def dataset
        read("dataset")
      end

      def skip
        read("skip")
      end

      def top
        read("top")
      end

      # Agent 365 agentLifecycle event value fields. The service sends the
      # agenticAppInstanceId / agentIdentityBlueprintId wire keys (not the
      # account-style names); all SDKs preserve them.
      def tenant_id
        read("tenantId", "tenant_id")
      end

      def agentic_user_id
        read("agenticUserId", "agentic_user_id")
      end

      def agentic_app_instance_id
        read("agenticAppInstanceId", "agentic_app_instance_id")
      end

      def agent_identity_blueprint_id
        read("agentIdentityBlueprintId", "agent_identity_blueprint_id")
      end

      def version
        read("version")
      end

      # Variant extras: manager (identity-created carries userId/email/
      # displayName; manager-updated carries managerId), deletion reason,
      # workload onboarding fields, and the created identity's expiry.
      def manager
        value = read("manager")
        value.is_a?(Hash) ? ActivityValue.new(value) : value
      end

      def user_id
        read("userId", "user_id")
      end

      def email
        read("email")
      end

      def display_name
        read("displayName", "display_name")
      end

      def manager_id
        read("managerId", "manager_id")
      end

      def deletion_reason
        read("deletionReason", "deletion_reason")
      end

      def workload_name
        read("workloadName", "workload_name")
      end

      def workload_onboarding_state
        read("workloadOnboardingState", "workload_onboarding_state")
      end

      def expiration_date_time
        read("expirationDateTime", "expiration_date_time")
      end
    end
  end
end
