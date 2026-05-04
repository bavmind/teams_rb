# frozen_string_literal: true

module Teams
  module Api
    class ConversationAccount < Model
      def id
        read("id")
      end

      def tenant_id
        read("tenantId", "tenant_id")
      end

      def conversation_type
        read("conversationType", "conversation_type")
      end

      def name
        read("name")
      end

      def is_group
        read("isGroup", "is_group")
      end

      def to_h
        body = raw.dup
        body["id"] = id if id
        body["tenantId"] = tenant_id if tenant_id
        body["conversationType"] = conversation_type if conversation_type
        body["name"] = name if name
        body["isGroup"] = is_group unless is_group.nil?
        body.delete("tenant_id")
        body.delete("conversation_type")
        body.delete("is_group")
        body
      end
    end
  end
end
