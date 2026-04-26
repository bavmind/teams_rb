# frozen_string_literal: true

module Teams
  Response = Struct.new(:status, :body, :headers, keyword_init: true) do
    def initialize(status: 200, body: nil, headers: {})
      super(status:, body:, headers:)
    end
  end
end
