# frozen_string_literal: true

module Teams
  module Api
    # An attachment in a message extension result; preview: carries the
    # optional preview card shown in the result list.
    class MessagingExtensionAttachment
      def initialize(content_type: nil, content: nil, content_url: nil, name: nil,
                     thumbnail_url: nil, preview: nil)
        @content_type = content_type
        @content = content
        @content_url = content_url
        @name = name
        @thumbnail_url = thumbnail_url
        @preview = preview
      end

      def to_h
        body = {}
        body["contentType"] = @content_type if @content_type
        body["content"] = serialize(@content) if @content
        body["contentUrl"] = @content_url if @content_url
        body["name"] = @name if @name
        body["thumbnailUrl"] = @thumbnail_url if @thumbnail_url
        body["preview"] = serialize(@preview) if @preview
        body
      end

      private

      def serialize(value)
        value = value.to_h if value.respond_to?(:to_h) && !value.is_a?(Hash)
        value.is_a?(Hash) ? Common::Hashes.deep_stringify_keys(value) : value
      end
    end

    # type: "result", "auth", "config", "message", "botMessagePreview", or
    # "silentAuth"; attachment_layout: "list" or "grid".
    class MessagingExtensionResult
      def initialize(type: nil, attachment_layout: nil, attachments: nil,
                     suggested_actions: nil, text: nil, activity_preview: nil)
        @type = type
        @attachment_layout = attachment_layout
        @attachments = attachments
        @suggested_actions = suggested_actions
        @text = text
        @activity_preview = activity_preview
      end

      def to_h
        body = {}
        body["type"] = @type if @type
        body["attachmentLayout"] = @attachment_layout if @attachment_layout
        body["attachments"] = @attachments.map { |attachment| serialize(attachment) } if @attachments
        body["suggestedActions"] = serialize(@suggested_actions) if @suggested_actions
        body["text"] = @text if @text
        body["activityPreview"] = serialize(@activity_preview) if @activity_preview
        body
      end

      private

      def serialize(value)
        value = value.to_h if value.respond_to?(:to_h) && !value.is_a?(Hash)
        value.is_a?(Hash) ? Common::Hashes.deep_stringify_keys(value) : value
      end
    end

    # Response for the query-style message extension invokes (query,
    # selectItem, queryLink, querySettingUrl, setting).
    class MessagingExtensionResponse
      def initialize(compose_extension, cache_info: nil)
        @compose_extension = compose_extension
        @cache_info = cache_info
      end

      def to_h
        body = {}
        if @compose_extension
          body["composeExtension"] =
            @compose_extension.respond_to?(:to_h) ? @compose_extension.to_h : @compose_extension
        end
        body["cacheInfo"] = Common::Hashes.deep_stringify_keys(@cache_info) if @cache_info
        body
      end
    end

    # Response for the action-style invokes (submitAction, fetchTask):
    # either a dialog via task: (a TaskModuleContinueResponse /
    # TaskModuleMessageResponse) or a result via compose_extension:.
    class MessagingExtensionActionResponse
      def initialize(task: nil, compose_extension: nil, cache_info: nil)
        @task = task
        @compose_extension = compose_extension
        @cache_info = cache_info
      end

      def to_h
        body = {}
        body["task"] = @task.respond_to?(:to_h) ? @task.to_h : @task if @task
        if @compose_extension
          body["composeExtension"] =
            @compose_extension.respond_to?(:to_h) ? @compose_extension.to_h : @compose_extension
        end
        body["cacheInfo"] = Common::Hashes.deep_stringify_keys(@cache_info) if @cache_info
        body
      end
    end
  end
end
