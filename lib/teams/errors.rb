# frozen_string_literal: true

module Teams
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class AuthenticationError < Error; end

  class BadRequestError < Error; end

  # Deprecated: Teams no longer supports stopping a stream, so the SDK never
  # raises this. Kept so existing rescue clauses keep loading.
  class StreamCancelledError < Error; end

  # Base class for terminal streaming errors (HTTP 403) that should not be retried.
  # https://learn.microsoft.com/en-us/microsoftteams/platform/bots/streaming-ux#response-codes
  class TerminalStreamError < Error; end

  # Raised when the bot failed to complete streaming within the ten-minute limit.
  class StreamTimedOutError < TerminalStreamError; end

  # Raised when streaming is not allowed for this user or bot.
  class StreamNotAllowedError < TerminalStreamError; end

  # Base class for the diagnosable failures on the inbound-file path, so one
  # rescue covers them. A transport or service failure the SDK cannot
  # attribute surfaces as a plain Teams::Error instead.
  class FileError < Error; end

  # An inbound file's short-lived download URL expired. reason is
  # "first_fetch" (no bytes were ever fetched; the file has to be sent again)
  # or "reread" (an earlier download through the same handle succeeded; reuse
  # one DownloadedFile instead of re-reading the handle).
  class FileUrlExpiredError < FileError
    attr_reader :reason

    def initialize(reason, message = nil)
      message ||= if reason == "first_fetch"
        "file download URL expired before any bytes were fetched. The URL is short-lived and cannot be " \
          "renewed, so the file has to be sent again. Download on arrival rather than holding the handle."
      else
        "file download URL expired before a repeat read; reuse a single DownloadedFile from one " \
          "download call instead of re-reading the handle"
      end
      super(message)
      @reason = reason
    end
  end

  # File bytes were requested for a conversation scope whose download path
  # is not implemented.
  class FileScopeNotSupportedError < FileError
    attr_reader :scope

    def initialize(scope, message = nil)
      super(message || "downloading files from '#{scope}' conversations is not supported via SDK at this time")
      @scope = scope
    end
  end

  # A failed Microsoft Graph request; code carries the Graph error code
  # (e.g. "Authorization_RequestDenied") and body the full error payload.
  class GraphError < Error
    attr_reader :status, :code, :body

    def initialize(message, status:, code: nil, body: nil)
      super(message)
      @status = status
      @code = code
      @body = body
    end
  end

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
