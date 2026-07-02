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
  end
end
