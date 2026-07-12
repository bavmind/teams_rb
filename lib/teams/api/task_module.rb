# frozen_string_literal: true

module Teams
  module Api
    # Dialog (task module) content definition: either a card dialog (card:)
    # or a webpage dialog (url:). height/width take "small"/"medium"/"large"
    # or pixel integers.
    class TaskModuleTaskInfo
      def initialize(title: nil, height: nil, width: nil, url: nil, card: nil,
                     fallback_url: nil, completion_bot_id: nil)
        @title = title
        @height = height
        @width = width
        @url = url
        @card = card
        @fallback_url = fallback_url
        @completion_bot_id = completion_bot_id
      end

      def to_h
        body = {}
        body["title"] = @title if @title
        body["height"] = @height if @height
        body["width"] = @width if @width
        body["url"] = @url if @url
        body["card"] = card_attachment(@card) if @card
        body["fallbackUrl"] = @fallback_url if @fallback_url
        body["completionBotId"] = @completion_bot_id if @completion_bot_id
        body
      end

      private

      # Accepts a ready attachment hash, or a card (Cards::AdaptiveCard or
      # hash) which is wrapped like MessageActivity#add_card.
      def card_attachment(card)
        card = card.to_h if card.respond_to?(:to_h) && !card.is_a?(Hash)
        return Common::Hashes.deep_stringify_keys(card) if card.is_a?(Hash) && card.key?("contentType")

        {
          "contentType" => "application/vnd.microsoft.card.adaptive",
          "content" => card.is_a?(Hash) ? Common::Hashes.deep_stringify_keys(card) : card
        }
      end
    end

    class TaskModuleContinueResponse
      def initialize(value)
        @value = value
      end

      def to_h
        {
          "type" => "continue",
          "value" => @value.respond_to?(:to_h) ? @value.to_h : @value
        }
      end
    end

    class TaskModuleMessageResponse
      def initialize(value)
        @value = value
      end

      def to_h
        { "type" => "message", "value" => @value.to_s }
      end
    end

    class TaskModuleResponse
      def initialize(task, cache_info: nil)
        @task = task
        @cache_info = cache_info
      end

      def to_h
        body = { "task" => @task.respond_to?(:to_h) ? @task.to_h : @task }
        body["cacheInfo"] = Common::Hashes.deep_stringify_keys(@cache_info) if @cache_info
        body
      end
    end
  end
end
