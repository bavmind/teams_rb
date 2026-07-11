# frozen_string_literal: true

require "json"

module Teams
  module Cards
    # Base class for the generated Adaptive Card models. Serialization matches
    # the other Teams SDKs' generated card classes: non-nil fields (including
    # defaults) are emitted under their camelCase aliases, unknown extra
    # fields pass through verbatim.
    class GeneratedCard
      OMIT = Object.new.freeze

      class << self
        def card_fields
          @card_fields ||= superclass.respond_to?(:card_fields) ? superclass.card_fields.dup : {}
        end

        def field(name, alias_name, default = nil, mutable: false)
          card_fields[name] = { alias: alias_name, default:, mutable: }

          define_method(name) { @values[name] }
          define_method("#{name}=") { |value| @values[name] = value }
          define_method("with_#{name}") do |value|
            @values[name] = value
            self
          end
        end

        # Ruby convenience preserved from the original hand-written classes:
        # allows the first constructor argument to set the given field.
        def positional_field(name)
          define_method(:initialize) do |positional = OMIT, **values|
            values[name] = positional unless positional.equal?(OMIT)
            super(**values)
          end
        end

        # Same, for classes whose hand-written predecessors took a splat.
        def splat_field(name)
          define_method(:initialize) do |*positional, **values|
            values[name] = positional.flatten unless positional.empty?
            super(**values)
          end
        end

        def array_adder(method_name, field_name)
          define_method(method_name) do |item|
            (@values[field_name] ||= []) << item
            self
          end
        end
      end

      def initialize(**values)
        @values = {}
        self.class.card_fields.each do |name, spec|
          @values[name] = if values.key?(name)
            values.delete(name)
          elsif spec[:mutable]
            deep_dup(spec[:default])
          else
            spec[:default]
          end
        end
        values.each { |key, value| @values[key] = value }
      end

      def to_h
        @values.each_with_object({}) do |(name, value), body|
          next if value.nil?

          spec = self.class.card_fields[name]
          body[spec ? spec[:alias] : camelize(name.to_s)] = serialize(value)
        end
      end

      def to_json(*args)
        JSON.generate(to_h, *args)
      end

      private

      def serialize(value)
        case value
        when Array
          value.map { |item| serialize(item) }
        when Hash
          value.each_with_object({}) { |(key, item), hash| hash[key.to_s] = serialize(item) }
        else
          value.respond_to?(:to_h) && !value.is_a?(Numeric) ? value.to_h : value
        end
      end

      def deep_dup(value)
        Marshal.load(Marshal.dump(value))
      end

      def camelize(key)
        parts = key.split("_")
        parts.first + parts.drop(1).map(&:capitalize).join
      end
    end
  end
end
