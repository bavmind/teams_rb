# frozen_string_literal: true

require "json"

module Teams
  module Cards
    class CardObject
      attr_reader :options

      def initialize(**options)
        @options = options
      end

      def to_h
        compact_hash(serialize_options(options))
      end

      def to_json(*args)
        JSON.generate(to_h, *args)
      end

      def with_options(options = nil, **kwargs)
        options = (options || {}).merge(kwargs)
        options.each { |key, value| with_option(key, value) }
        self
      end

      private

      def with_option(key, value)
        options[key] = value
        self
      end

      def serialize(value)
        case value
        when nil
          nil
        when Array
          value.map { |item| serialize(item) }
        when Hash
          serialize_options(value)
        else
          value.respond_to?(:to_h) ? value.to_h : value
        end
      end

      def serialize_options(values)
        values.each_with_object({}) do |(key, value), hash|
          hash[json_key(key)] = serialize(value)
        end
      end

      def compact_hash(hash)
        hash.reject { |_key, value| value.nil? }
      end

      def json_key(key)
        return key if key.is_a?(String)

        case key
        when :schema
          "$schema"
        when :choices_data
          "choices.data"
        when :grid_area
          "grid.area"
        else
          camelize(key)
        end
      end

      def camelize(key)
        parts = key.to_s.split("_")
        parts.first + parts.drop(1).map(&:capitalize).join
      end
    end

    class AdaptiveCard < CardObject
      def initialize(*body, version: "1.5", actions: nil, **options)
        super(**options)
        @body = body.flatten
        @actions = actions
        @version = version
      end

      def with_body(*body)
        @body = body.flatten
        self
      end

      def with_actions(*actions)
        @actions = actions.flatten
        self
      end

      def add_item(item)
        @body << item
        self
      end

      def add_action(action)
        @actions ||= []
        @actions << action
        self
      end

      def to_h
        compact_hash(
          super.merge(
            "type" => "AdaptiveCard",
            "version" => @version,
            "body" => serialize(@body),
            "actions" => serialize(@actions)
          )
        )
      end
    end

    class TextBlock < CardObject
      def initialize(text, **options)
        super(**options)
        @text = text
      end

      def with_text(text)
        @text = text
        self
      end

      def to_h
        super.merge("type" => "TextBlock", "text" => @text)
      end
    end

    class TextInput < CardObject
      def initialize(id: nil, **options)
        super(**options)
        @id = id
      end

      def with_id(id)
        @id = id
        self
      end

      def to_h
        compact_hash(super.merge("type" => "Input.Text", "id" => @id))
      end
    end

    class ChoiceSetInput < CardObject
      def initialize(*choices, id: nil, **options)
        super(**options)
        @choices = choices.flatten
        @id = id
      end

      def with_id(id)
        @id = id
        self
      end

      def with_choices(*choices)
        @choices = choices.flatten
        self
      end

      def add_choice(choice)
        @choices << choice
        self
      end

      def to_h
        compact_hash(
          super.merge(
            "type" => "Input.ChoiceSet",
            "id" => @id,
            "choices" => serialize(@choices)
          )
        )
      end
    end

    class Choice < CardObject
      def initialize(title: nil, value: nil, **options)
        super(**options)
        @title = title
        @value = value
      end

      def with_title(title)
        @title = title
        self
      end

      def with_value(value)
        @value = value
        self
      end

      def to_h
        compact_hash(super.merge("title" => @title, "value" => @value))
      end
    end

    class ActionSet < CardObject
      def initialize(*actions, **options)
        super(**options)
        @actions = actions.flatten
      end

      def with_actions(*actions)
        @actions = actions.flatten
        self
      end

      def add_action(action)
        @actions << action
        self
      end

      def to_h
        super.merge("type" => "ActionSet", "actions" => serialize(@actions))
      end
    end

    class Action < CardObject
      def initialize(title: nil, **options)
        super(**options)
        @title = title
      end

      def with_title(title)
        @title = title
        self
      end

      def common_h(type)
        compact_hash(serialize_options(options).merge("type" => type, "title" => @title))
      end
    end

    class SubmitAction < Action
      def initialize(title: nil, data: nil, **options)
        super(title:, **options)
        @data = data
      end

      def with_data(data)
        @data = data
        self
      end

      def to_h
        compact_hash(common_h("Action.Submit").merge("data" => serialize(@data)))
      end
    end

    class ExecuteAction < Action
      def initialize(title: nil, data: nil, verb: nil, **options)
        super(title:, **options)
        @data = data
        @verb = verb
      end

      def with_data(data)
        @data = data
        self
      end

      def with_verb(verb)
        @verb = verb
        self
      end

      def to_h
        compact_hash(common_h("Action.Execute").merge("data" => serialize(@data), "verb" => @verb))
      end
    end

    class OpenUrlAction < Action
      def initialize(url, title: nil, **options)
        super(title:, **options)
        @url = url
      end

      def with_url(url)
        @url = url
        self
      end

      def to_h
        common_h("Action.OpenUrl").merge("url" => @url)
      end
    end
  end
end
