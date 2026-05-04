# frozen_string_literal: true

module Teams
  module Api
    class Account < Model
      def id
        read("id")
      end

      def name
        read("name")
      end

      def aad_object_id
        read("aadObjectId", "objectId", "aad_object_id")
      end

      def type
        read("type")
      end

      def properties
        read("properties")
      end

      def is_targeted
        read("isTargeted", "is_targeted")
      end

      def role
        read("role")
      end

      def user_role
        read("userRole", "user_role")
      end

      def given_name
        read("givenName", "given_name")
      end

      def surname
        read("surname")
      end

      def email
        read("email")
      end

      def user_principal_name
        read("userPrincipalName", "user_principal_name")
      end

      def tenant_id
        read("tenantId", "tenant_id")
      end

      def to_h
        body = raw.dup
        body["id"] = id if id
        body["name"] = name if name
        body["aadObjectId"] = aad_object_id if aad_object_id
        body["type"] = type if type
        body["properties"] = properties if properties
        body["isTargeted"] = is_targeted unless is_targeted.nil?
        body["role"] = role if role
        body["userRole"] = user_role if user_role
        body["givenName"] = given_name if given_name
        body["surname"] = surname if surname
        body["email"] = email if email
        body["userPrincipalName"] = user_principal_name if user_principal_name
        body["tenantId"] = tenant_id if tenant_id
        remove_aliases(body)
      end

      private

      def remove_aliases(body)
        body.delete("objectId")
        body.delete("aad_object_id")
        body.delete("is_targeted")
        body.delete("user_role")
        body.delete("given_name")
        body.delete("user_principal_name")
        body.delete("tenant_id")
        body
      end
    end
  end
end
