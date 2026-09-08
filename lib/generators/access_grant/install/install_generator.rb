# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module AccessGrant
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)
      desc "Creates AccessGrant core tables migration (short default names)"

      def copy_migration
        migration_template(
          "create_access_grant_tables.rb.tt",
          File.join(db_migrate_path, "create_access_grant_tables.rb")
        )
      end
    end
  end
end
