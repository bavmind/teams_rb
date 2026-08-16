# frozen_string_literal: true

module Teams
  module Api
    # The Agent 365 identity scope for SDK operations: an agentic app
    # blueprint (the app registration itself), optionally narrowed to an
    # agentic app instance and an agentic user attached to that instance.
    class AgenticIdentity
      attr_reader :agentic_app_blueprint_id, :agentic_app_id, :agentic_user_id, :tenant_id

      def initialize(agentic_app_blueprint_id:, agentic_app_id: nil, agentic_user_id: nil, tenant_id: nil)
        @agentic_app_blueprint_id = agentic_app_blueprint_id
        @agentic_app_id = agentic_app_id
        @agentic_user_id = agentic_user_id
        @tenant_id = tenant_id
      end

      def to_h
        body = { "agenticAppBlueprintId" => agentic_app_blueprint_id }
        body["agenticAppId"] = agentic_app_id if agentic_app_id
        body["agenticUserId"] = agentic_user_id if agentic_user_id
        body["tenantId"] = tenant_id if tenant_id
        body
      end
    end
  end
end
