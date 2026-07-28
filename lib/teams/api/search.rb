# frozen_string_literal: true

module Teams
  module Api
    # A single application/search result: title is the display text, value
    # is submitted when the user selects it.
    class SearchInvokeResult
      def initialize(title:, value:)
        @title = title
        @value = value
      end

      def to_h
        { "title" => @title, "value" => @value }
      end
    end

    # Response body for application/search invokes (Adaptive Card dynamic
    # typeahead Input.ChoiceSet queries). results accepts SearchInvokeResult
    # objects or {title:, value:} hashes.
    class SearchResponse
      def initialize(results, status_code: 200)
        @results = results
        @status_code = status_code
      end

      def to_h
        {
          "statusCode" => @status_code,
          "type" => "application/vnd.microsoft.search.searchResponse",
          "value" => {
            "results" => Array(@results).map do |result|
              body = result.is_a?(Hash) ? result : result.to_h
              Common::Hashes.deep_stringify_keys(body)
            end
          }
        }
      end
    end
  end
end
