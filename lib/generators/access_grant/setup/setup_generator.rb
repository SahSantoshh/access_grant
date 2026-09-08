# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module AccessGrant
  module Generators
    class SetupGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)
      desc "Configures AccessGrant (initializer, catalog, user_roles, model patches)"

      class_option :multi_tenant, type: :boolean, default: nil,
                                  desc: "Multi-tenant install (roles scoped by tenant)"
      class_option :single_tenant, type: :boolean, default: nil,
                                   desc: "Single-tenant install (no tenant_class)"
      class_option :tenant, type: :string, default: "Organization",
                            desc: "Tenant model class name"
      class_option :user, type: :string, default: "User",
                          desc: "User model class name"
      class_option :owner_role, type: :string, default: "protected",
                                desc: "Owner mode: protected, bypass, both, or none"
      class_option :tables, type: :string, default: "auto",
                            desc: "Table naming: auto, simple, or prefixed"

      SHORT_TABLES = {
        roles: "roles",
        permissions: "permissions",
        role_permissions: "role_permissions",
        user_roles: "user_roles"
      }.freeze

      PREFIXED_TABLES = {
        roles: "access_grant_roles",
        permissions: "access_grant_permissions",
        role_permissions: "access_grant_role_permissions",
        user_roles: "access_grant_user_roles"
      }.freeze

      def resolve_options!
        @multi_tenant = resolve_multi_tenant!
        @tenant_class = @multi_tenant ? options[:tenant] : nil
        @user_class = options[:user]
        @owner_role = options[:owner_role].to_sym
        @tables = resolve_tables!
      end

      def create_initializer
        template "access_grant.rb.tt", "config/initializers/access_grant.rb"
      end

      def create_permissions_catalog
        template "permissions.rb.tt", "config/access_grant/permissions.rb"
      end

      def create_roles_config
        template "roles.rb.tt", "config/access_grant/roles.rb"
      end

      def create_user_roles_migration
        @user_roles_table = @tables.fetch(:user_roles)
        @roles_table = @tables.fetch(:roles)
        migration_template(
          "create_access_grant_user_roles.rb.tt",
          File.join(db_migrate_path, "create_access_grant_user_roles.rb")
        )
      end

      def patch_models
        inject_access_grant(@tenant_class, :tenant) if @multi_tenant
        inject_access_grant(@user_class, :user)
      end

      def print_deploy_reminder
        say ""
        say "IMPORTANT — catalog sync is not a migration.", :yellow
        say "After migrate, and on every deploy that may change permissions.rb, run:"
        say "  bundle exec rake access_grant:sync_permissions", :green
        say "Wire this into your release process (Kamal / Heroku release / Capistrano)."
        say ""
        return unless @tables != SHORT_TABLES

        say "Table names differ from access_grant:install defaults (short names).", :yellow
        say "Edit the install migration's table names to match config.tables before db:migrate.", :yellow
        say ""
      end

      private

      def resolve_multi_tenant!
        if options[:multi_tenant]
          true
        elsif options[:single_tenant]
          false
        elsif options[:multi_tenant].nil? && options[:single_tenant].nil?
          yes?("Multi-tenant install? (y/n)")
        else
          false
        end
      end

      def resolve_tables!
        strategy = options[:tables].to_s
        case strategy
        when "prefixed"
          PREFIXED_TABLES.dup
        when "simple"
          fail_if_short_taken!
          SHORT_TABLES.dup
        when "auto"
          if short_names_taken?
            say_status :collision, "short table/model names taken → access_grant_*", :yellow
            PREFIXED_TABLES.dup
          else
            unless connection_available?
              say_status :info,
                         "no DB connection — assuming short table names are free " \
                         "(--tables=auto); use --tables=prefixed if they may collide",
                         :blue
            end
            SHORT_TABLES.dup
          end
        else
          raise Thor::Error, "Unknown --tables=#{strategy.inspect} (use auto|simple|prefixed)"
        end
      end

      def short_names_taken?
        SHORT_TABLES.each_value.any? { |name| table_exists_safe?(name) } ||
          %w[Role Permission].any? { |const| Object.const_defined?(const, false) }
      end

      def fail_if_short_taken!
        return unless short_names_taken?

        raise Thor::Error,
              "Short table/model names are taken (roles/permissions/role_permissions/" \
              "user_roles or top-level Role/Permission). " \
              "Use --tables=auto or --tables=prefixed instead of --tables=simple."
      end

      def connection_available?
        defined?(ActiveRecord::Base) &&
          ActiveRecord::Base.connected? &&
          ActiveRecord::Base.connection
      rescue StandardError
        false
      end

      def table_exists_safe?(name)
        return false unless connection_available?

        ActiveRecord::Base.connection.table_exists?(name)
      rescue StandardError
        false
      end

      def inject_access_grant(class_name, role)
        path = model_path_for(class_name)
        unless path && File.exist?(path)
          say_status :warn, "could not find model file for #{class_name} — add `access_grant :#{role}` manually",
                     :yellow
          return
        end

        marker = "access_grant :#{role}"
        if File.read(path).include?(marker)
          say_status :identical, "#{path} already has #{marker}", :blue
          return
        end

        inject_into_class(path, class_name.to_s.demodulize, "  #{marker}\n")
      end

      def model_path_for(class_name)
        return nil if class_name.nil? || class_name.to_s.empty?

        relative = class_name.to_s.underscore
        candidates = [
          File.join(destination_root, "app/models/#{relative}.rb"),
          File.join(destination_root, "app/models/#{relative.split('/').last}.rb")
        ]
        candidates.find { |p| File.exist?(p) }
      end

      # Template helpers
      def multi_tenant? = @multi_tenant
      attr_reader :tenant_class, :user_class, :owner_role, :tables
    end
  end
end
