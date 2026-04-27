# frozen_string_literal: true

module Teams
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class AuthenticationError < Error; end

  class ServiceUrlError < Error; end

  class BadRequestError < Error; end
  class StreamCancelledError < Error; end

  class HttpError < Error
    attr_reader :status, :headers, :body, :request

    def initialize(message, status:, headers:, body:, request: nil)
      super(message)
      @status = status
      @headers = headers
      @body = body
      @request = request
    end
  end
end
