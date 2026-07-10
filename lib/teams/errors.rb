# frozen_string_literal: true

module Teams
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class AuthenticationError < Error; end

  class ServiceUrlError < Error; end

  class BadRequestError < Error; end

  # Raised when Teams cancels a stream (for example, the user pressed Stop)
  # or when a stream operation is attempted after cancellation.
  class StreamCancelledError < Error; end

  # Base class for terminal streaming errors (HTTP 403) that should not be retried.
  # https://learn.microsoft.com/en-us/microsoftteams/platform/bots/streaming-ux?tabs=csharp#error-codes
  class TerminalStreamError < Error; end

  # Raised when the bot failed to complete streaming within the two-minute limit.
  class StreamTimedOutError < TerminalStreamError; end

  # Raised when streaming is not allowed for this user or bot.
  class StreamNotAllowedError < TerminalStreamError; end

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
