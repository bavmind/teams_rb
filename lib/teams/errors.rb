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

  # Names the identity a file read was attempted as ("app" or
  # "agentic_user") in error messages.
  module FileActorGuidance
    private

    def describe_actor(actor)
      case actor
      when "agentic_user" then "the agentic user"
      when "app" then "the app"
      else "the identity used"
      end
    end
  end

  # No credential was available for the Graph read a file needs, detected
  # before any request: a token could not be acquired (cause says why), or
  # the acquired token carries no file-capable permission.
  class FileCredentialError < FileError
    attr_reader :actor, :cause_detail

    def initialize(actor = nil, cause_detail = nil)
      message = "cannot fetch file bytes through Graph: #{guidance(actor)}"
      message = "#{message} (#{cause_detail})" if cause_detail
      super(message)
      @actor = actor
      @cause_detail = cause_detail
    end

    private

    def guidance(actor)
      case actor
      when "agentic_user"
        "the agentic user has no usable Graph permissions. An agent identity gets Graph scopes from its " \
          "blueprint's inheritable permissions or from a direct grant, and an administrator must consent to them. " \
          "See https://learn.microsoft.com/entra/agent-id/concept-inheritable-permissions"
      when "app"
        "the app has no usable Graph credential for this file. Graph file retrieval is supported for Agentic " \
          "Users, which read as their own identity; an app identity and/or user-delegated permissions may be " \
          "used but are not supported via the SDK at this time"
      else
        "no Graph credential was available, and no identity had been selected when the attempt was made"
      end
    end
  end

  # The storage service refused the Graph read. status 401 means the token
  # was rejected; 403 means the identity lacks the grant, which also covers a
  # file never shared with it and an item that does not exist (Graph does not
  # tell them apart). details carries what the service said.
  class FileAccessError < FileError
    include FileActorGuidance

    attr_reader :status, :actor, :details

    def initialize(status, actor = nil, details = nil)
      message = "cannot fetch file bytes through Graph: #{guidance(status, actor)}"
      message = "#{message} (service said: #{details})" if details
      super(message)
      @status = status
      @actor = actor
      @details = details
    end

    private

    def guidance(status, actor)
      as_who = describe_actor(actor)
      case status
      when 401
        "the token presented for #{as_who} was rejected. It may have expired, or been issued for the wrong " \
          "audience or tenant"
      when 403
        "access was denied for #{as_who}. The required scope may not be consented, the file may never have been " \
          "shared with that identity, or the drive item may not exist"
      else
        "the request for #{as_who} was refused with status #{status}"
      end
    end
  end

  # The Teams service could not convert a pasted image for download (415).
  # Some formats, such as BMP and AVIF, cannot be converted; the same image
  # sent as a file attachment downloads normally. code is the service's error
  # code (e.g. "TransformationFailed").
  class InlineImageTransformationError < FileError
    attr_reader :status, :actor, :details, :code

    def initialize(status, actor = nil, details = nil, code = nil)
      reason = code ? "status #{status}, code #{code}" : "status #{status}"
      message = "cannot download inline image: the Teams service could not convert it for download (#{reason}). " \
        "Some image formats, such as BMP and AVIF, cannot be converted by the Teams service, so Teams shows a " \
        "placeholder, and they cannot be downloaded. Ask the user to send the image as a file attachment instead"
      message = "#{message} (service said: #{details})" if details
      super(message)
      @status = status
      @actor = actor
      @details = details
      @code = code
    end
  end

  # The Bot API refused the token presented for a pasted image: 401 means
  # the token was rejected, 403 that the identity may not read the image.
  # Inline images are read with the turn's Bot API token, not Graph.
  class InlineImageAccessError < FileError
    include FileActorGuidance

    attr_reader :status, :actor, :details

    def initialize(status, actor = nil, details = nil)
      message = "cannot download inline image: #{guidance(status, actor)}"
      message = "#{message} (service said: #{details})" if details
      super(message)
      @status = status
      @actor = actor
      @details = details
    end

    private

    def guidance(status, actor)
      as_who = describe_actor(actor)
      case status
      when 401
        "the Bot API token presented for #{as_who} was rejected (status 401). " \
          "It may have expired, or been issued for the wrong audience or tenant"
      when 403
        "access was denied for #{as_who} (status 403). The identity is not allowed to read the image"
      else
        "the Bot API token presented for #{as_who} was rejected with status #{status}"
      end
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
