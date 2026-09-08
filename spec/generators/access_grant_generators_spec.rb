# frozen_string_literal: true

require "tempfile"
require "active_support"
require "active_support/core_ext/string/inflections"
require "rails/generators"
require "rails/generators/testing/behavior"
require "rails/generators/testing/setup_and_teardown"
require "fileutils"

require_relative "../../lib/generators/access_grant/install/install_generator"
require_relative "../../lib/generators/access_grant/setup/setup_generator"

RSpec.describe "AccessGrant generators smoke" do
  include Rails::Generators::Testing::Behavior
  include Rails::Generators::Testing::SetupAndTeardown
  include FileUtils

  destination File.expand_path("../../tmp/generators", __dir__)

  before { prepare_destination }

  def write_model(class_name)
    relative = class_name.underscore
    path = File.join(destination_root, "app/models/#{relative}.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, <<~RUBY)
      class #{class_name} < ApplicationRecord
      end
    RUBY
  end

  def migration_matching(basename)
    Dir.glob(File.join(destination_root, "db/migrate/*_#{basename}.rb")).first
  end

  def read!(relative)
    path = File.join(destination_root, relative)
    expect(File).to exist(path), "expected #{relative} to exist"
    File.read(path)
  end

  def stub_short_names_free!
    # Spec DB already has short AccessGrant tables; pretend they are free for --tables=simple.
    allow(ActiveRecord::Base.connection).to receive(:table_exists?).and_return(false)
  end

  it "install + setup create expected files in destination_root" do
    write_model("Organization")
    write_model("User")
    stub_short_names_free!

    self.class.tests AccessGrant::Generators::InstallGenerator
    run_generator

    install_migration = migration_matching("create_access_grant_tables")
    expect(install_migration).to be_present
    install_content = File.read(install_migration)
    expect(install_content).to include("create_table :permissions")
    expect(install_content).to include("create_table :roles")
    expect(install_content).to include("t.bigint :tenant_id")
    expect(install_content).to include("create_table :role_permissions")

    self.class.tests AccessGrant::Generators::SetupGenerator
    run_generator %w[
      --multi-tenant
      --tenant=Organization
      --user=User
      --owner-role=protected
      --tables=simple
    ]

    initializer = read!("config/initializers/access_grant.rb")
    expect(initializer).to include('config.tenant_class = "Organization"')
    expect(initializer).to include('config.user_class = "User"')
    expect(initializer).to include("config.owner_role = :protected")
    expect(initializer).to include("config.owner_role_name")
    expect(initializer).to include("config.tables")
    expect(initializer).to include("config.default_permission_actions")
    expect(initializer).to include("config.current_user_method")
    expect(initializer).to include("config.current_tenant_method")
    expect(initializer).to include("config.on_tenant_created")
    expect(initializer).to include("config.recover_access")
    expect(initializer).to include('roles: "roles"')

    expect(read!("config/access_grant/permissions.rb")).to include("resource :invoices")
    expect(read!("config/access_grant/roles.rb")).to include("ensure_resource_defaults_for!")

    user_roles = migration_matching("create_access_grant_user_roles")
    expect(user_roles).to be_present
    expect(File.read(user_roles)).to include("create_table :user_roles")

    expect(read!("app/models/organization.rb")).to include("access_grant :tenant")
    expect(read!("app/models/user.rb")).to include("access_grant :user")
  end

  it "setup --tables=prefixed writes access_grant_* names and reminds to edit install migration" do
    write_model("User")

    self.class.tests AccessGrant::Generators::SetupGenerator
    output = run_generator %w[--single-tenant --user=User --tables=prefixed]

    initializer = read!("config/initializers/access_grant.rb")
    expect(initializer).to include('roles: "access_grant_roles"')
    expect(initializer).to include('user_roles: "access_grant_user_roles"')
    expect(initializer).to include("config.tenant_class = nil")

    user_roles = migration_matching("create_access_grant_user_roles")
    expect(user_roles).to be_present
    expect(File.read(user_roles)).to include("create_table :access_grant_user_roles")

    expect(output).to include("differ from access_grant:install defaults")
    expect(output).to include("match config.tables")
  end

  it "fails --tables=simple when short names are taken" do
    stub_const("Role", Class.new)
    write_model("User")

    generator = AccessGrant::Generators::SetupGenerator.new(
      [],
      { single_tenant: true, user: "User", tables: "simple" },
      destination_root: destination_root
    )

    expect do
      generator.invoke_all
    end.to raise_error(Thor::Error, %r{Short table/model names are taken})

    expect(File).not_to exist(File.join(destination_root, "config/initializers/access_grant.rb"))
  end
end
