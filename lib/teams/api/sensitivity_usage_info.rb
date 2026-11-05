# frozen_string_literal: true

module Teams
  module Api
    # A Microsoft Purview sensitivity label, identified by its label id. Teams
    # resolves the label's display name and description from the id and shows
    # it as a shield on the message. Used as the message-level label
    # (MessageActivity#add_sensitivity_label) and as a citation's usage info.
    # Mirrors the TypeScript, Python, and .NET SensitivityUsageInfo; at_id and
    # at_type follow Python's names for the @id and @type wire keys.
    class SensitivityUsageInfo
      attr_reader :at_id, :at_type, :name, :description, :position

      # name is the fallback display name when Teams cannot resolve at_id;
      # position is the label's priority, used to pick the most restrictive
      # label.
      def initialize(at_id:, name: nil, description: nil, position: nil, at_type: "CreativeWork")
        raise ArgumentError, "at_id (the Purview label id) is required" if at_id.nil?

        @at_id = at_id
        @at_type = at_type
        @name = name
        @description = description
        @position = position
      end

      def to_h
        {
          "@type" => at_type,
          "@id" => at_id,
          "name" => name,
          "description" => description,
          "position" => position
        }.compact
      end
    end
  end
end
