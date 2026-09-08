# frozen_string_literal: true

module AccessGrant
  class Catalog
    # DSL evaluated inside {AccessGrant.permissions} / {Catalog#replace}.
    #
    # @example
    #   AccessGrant.permissions do
    #     resource :invoices do
    #       action :couple, description: "Can couple invoices"
    #     end
    #     category "billing" do
    #       permission "billing.export", "Export billing CSV"
    #     end
    #   end
    class DSL
      # @param catalog [AccessGrant::Catalog]
      def initialize(catalog)
        @catalog = catalog
        @category_override = nil
        @current_resource = nil
        @default_keys = nil
        @explicit_keys = nil
        @satisfied_untemplated = nil
      end

      # Declare a resource; emits {AccessGrant::Configuration#default_permission_actions}
      # with description templates, then yields for custom actions.
      #
      # @param name [String, Symbol] singular or plural; stored segment is pluralized
      # @yield optional block for +action+ declarations
      # @return [void]
      def resource(name, &block)
        segment = name.to_s.pluralize
        category = @category_override || segment
        untemplated = untemplated_default_actions

        if block.nil? && untemplated.any?
          raise Error, "Default action :#{untemplated.first} requires an explicit description"
        end

        @current_resource = segment
        @default_keys = Set.new
        @explicit_keys = Set.new
        @satisfied_untemplated = Set.new
        emit_defaults(segment, category)
        instance_eval(&block) if block
        verify_untemplated_defaults!(untemplated) if block
      ensure
        @current_resource = nil
        @default_keys = nil
        @explicit_keys = nil
        @satisfied_untemplated = nil
      end

      # Nest declarations under an explicit category string (UI grouping).
      #
      # @param name [String, Symbol]
      # @yield
      # @return [void]
      def category(name, &)
        previous = @category_override
        @category_override = name.to_s
        instance_eval(&)
      ensure
        @category_override = previous
      end

      # Add or override an action under the current {#resource}.
      #
      # @param action_name [String, Symbol]
      # @param description [String] required
      # @param key [String, nil] optional full +resource.action+ override
      # @return [void]
      # @raise [AccessGrant::Error]
      def action(action_name, description: nil, key: nil)
        raise Error, "action requires a description" if description.nil?

        resource = @current_resource or raise Error, "action must be inside a resource block"

        permission_key = key || "#{resource}.#{action_name}"
        raise Error, "Duplicate permission key: #{permission_key}" if @explicit_keys.include?(permission_key)

        @explicit_keys.add(permission_key)
        mark_untemplated_satisfied(action_name, permission_key)
        category = @category_override || resource
        override = @default_keys.include?(permission_key)
        @catalog.add(permission_key, description: description, category: category, override: override)
      end

      # Ad-hoc catalog entry inside a {#category} block.
      #
      # @param key [String] must match +resource.action+
      # @param description [String]
      # @return [void]
      # @raise [AccessGrant::Error]
      def permission(key, description)
        category = @category_override or raise Error, "permission must be inside a category block"

        @catalog.add(key, description: description, category: category)
      end

      private

      def untemplated_default_actions
        AccessGrant.config.default_permission_actions.reject do |action|
          Catalog::DEFAULT_TEMPLATES.key?(action.to_s)
        end
      end

      def emit_defaults(segment, category)
        AccessGrant.config.default_permission_actions.each do |action|
          next unless Catalog::DEFAULT_TEMPLATES.key?(action.to_s)

          key = "#{segment}.#{action}"
          description = @catalog.template_description(action, segment)
          @catalog.add(key, description: description, category: category)
          @default_keys.add(key)
        end
      end

      def mark_untemplated_satisfied(action_name, permission_key)
        untemplated_default_actions.each do |action|
          if action_name.to_s == action.to_s || permission_key == "#{@current_resource}.#{action}"
            @satisfied_untemplated.add(action.to_s)
          end
        end
      end

      def verify_untemplated_defaults!(untemplated)
        missing = untemplated.map(&:to_s) - @satisfied_untemplated.to_a
        return if missing.empty?

        raise Error, "Default action :#{missing.first} requires an explicit description"
      end
    end
  end
end
