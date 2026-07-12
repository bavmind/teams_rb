# frozen_string_literal: true

module Teams
  class Router
    Route = Struct.new(:name, :selector, :handler, keyword_init: true)

    def initialize
      @routes = []
    end

    def use(&block)
      register(nil, ->(_activity) { true }, &block)
    end

    def on(name, &block)
      register(name.to_s, route_selector(name.to_s), &block)
    end

    def on_message(pattern = nil, &block)
      selector = lambda do |activity|
        next false unless activity.message?
        next true if pattern.nil?

        case pattern
        when Regexp
          pattern.match?(activity.text.to_s)
        else
          activity.text.to_s == pattern.to_s
        end
      end

      register("message", selector, &block)
    end

    def on_message_update(&block)
      register("messageUpdate", route_selector("messageUpdate"), &block)
    end

    def on_edit_message(&block)
      register("edit_message", message_update_event_selector("editMessage"), &block)
    end

    def on_undelete_message(&block)
      register("undelete_message", message_update_event_selector("undeleteMessage"), &block)
    end

    # Matches task/fetch invokes; with a dialog_id, only those whose card
    # action data carries that "dialog_id" value.
    def on_dialog_open(dialog_id = nil, &block)
      register("dialog.open", dialog_selector("task/fetch", "dialog_id", dialog_id), &block)
    end

    # Matches task/submit invokes; with an action, only those whose card
    # action data carries that "action" value.
    def on_dialog_submit(action = nil, &block)
      register("dialog.submit", dialog_selector("task/submit", "action", action), &block)
    end

    def on_signin_token_exchange(&block)
      register("signin.token-exchange", invoke_selector("signin/tokenExchange"), &block)
    end

    def on_signin_verify_state(&block)
      register("signin.verify-state", invoke_selector("signin/verifyState"), &block)
    end

    def on_signin_failure(&block)
      register("signin.failure", invoke_selector("signin/failure"), &block)
    end

    def on_message_submit(&block)
      register("message.submit", invoke_selector("message/submitAction"), &block)
    end

    # message/submitAction invokes whose actionName is "feedback" - the
    # submissions from add_feedback's thumbs up/down UI.
    def on_message_submit_feedback(&block)
      selector = lambda do |activity|
        activity.invoke? && activity.name == "message/submitAction" &&
          activity.raw.dig("value", "actionName") == "feedback"
      end
      register("message.submit.feedback", selector, &block)
    end

    def on_meeting_start(&block)
      register("meeting_start", event_selector("application/vnd.microsoft.meetingStart"), &block)
    end

    def on_meeting_end(&block)
      register("meeting_end", event_selector("application/vnd.microsoft.meetingEnd"), &block)
    end

    # Message extension (compose extension) invoke routes, using the same
    # route names as the TypeScript and Python SDKs.
    MESSAGE_EXTENSION_ROUTES = {
      "message.ext.query" => "composeExtension/query",
      "message.ext.select-item" => "composeExtension/selectItem",
      "message.ext.submit" => "composeExtension/submitAction",
      "message.ext.open" => "composeExtension/fetchTask",
      "message.ext.query-link" => "composeExtension/queryLink",
      "message.ext.anon-query-link" => "composeExtension/anonymousQueryLink",
      "message.ext.query-settings-url" => "composeExtension/querySettingUrl",
      "message.ext.setting" => "composeExtension/setting",
      "message.ext.card-button-clicked" => "composeExtension/onCardButtonClicked"
    }.freeze

    MESSAGE_EXTENSION_HANDLER_METHODS = MESSAGE_EXTENSION_ROUTES.keys.to_h do |route_name|
      ["on_#{route_name.sub("message.ext.", "message_ext_").tr("-", "_")}", route_name]
    end.freeze

    MESSAGE_EXTENSION_HANDLER_METHODS.each do |method_name, route_name|
      define_method(method_name) do |&block|
        register(route_name, invoke_selector(MESSAGE_EXTENSION_ROUTES.fetch(route_name)), &block)
      end
    end

    def matching(activity)
      @routes.select { |route| route.selector.call(activity) }
    end

    private

    def register(name, selector, &block)
      raise ArgumentError, "handler block is required" unless block

      @routes << Route.new(name:, selector:, handler: block)
      self
    end

    def route_selector(name)
      lambda do |activity|
        return true if name == "activity"
        return true if name == activity.type
        return true if name == "message" && activity.message?
        return true if name == "typing" && activity.typing?
        return true if name == "invoke" && activity.invoke?
        return true if name == "suggested-action.submit" && activity.suggested_action_submit?

        if activity.install_update?
          return true if name == "install.#{activity.raw["action"]}"
        end

        false
      end
    end

    def invoke_selector(invoke_name)
      ->(activity) { activity.invoke? && activity.name == invoke_name }
    end

    def event_selector(event_name)
      ->(activity) { activity.type == "event" && activity.name == event_name }
    end

    def dialog_selector(invoke_name, key, expected)
      lambda do |activity|
        next false unless activity.invoke? && activity.name == invoke_name
        next true if expected.nil?

        data = activity.raw.dig("value", "data")
        data.is_a?(Hash) && data[key] == expected
      end
    end

    def message_update_event_selector(event_type)
      lambda do |activity|
        activity.message_update? && activity.channel_data.event_type == event_type
      end
    end
  end
end
