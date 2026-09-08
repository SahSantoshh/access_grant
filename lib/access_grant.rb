# frozen_string_literal: true

require "active_record"

require_relative "access_grant/version"
require_relative "access_grant/configuration"
require_relative "access_grant/permission_key"
require_relative "access_grant/catalog"
require_relative "access_grant/sync"
require_relative "access_grant/owner"
require_relative "access_grant/recovery"
require_relative "access_grant/tenant"
require_relative "access_grant/user"
require_relative "access_grant/controller_methods"

# Database-backed, per-tenant roles and permissions for Rails.
#
# Configure once in an initializer, declare a permission catalog in code,
# sync into the DB, then check capabilities with {AccessGrant::User#permitted?}.
#
# @example Boot configuration
#   AccessGrant.configure do |config|
#     config.tenant_class = "Organization"
#     config.user_class = "User"
#     config.owner_role = :protected
#   end
#
# @see AccessGrant::Configuration
# @see docs/architecture.md
module AccessGrant
  # Base error for gem failures (unknown keys, Owner rules, etc.).
  class Error < StandardError; end

  # Raised by the controller authorize hook when the request is denied
  # (or when +permitted?+ fails with {Error} at the HTTP edge).
  class NotAuthorizedError < Error; end

  # @return [AccessGrant::Configuration] shared configuration singleton
  def self.config = @config ||= Configuration.new

  # Yields {#config}, then applies table names / tenant association.
  #
  # @yieldparam config [AccessGrant::Configuration]
  # @return [void]
  def self.configure
    yield(config)
    apply_configuration!
  end

  # Replace configuration with defaults and re-apply model wiring.
  # Intended for tests.
  #
  # @return [AccessGrant::Configuration]
  def self.reset_config!
    @config = Configuration.new
    apply_configuration!
  end

  # @return [AccessGrant::Catalog] in-memory permission catalog
  def self.catalog = @catalog ||= Catalog.new

  # Clear the in-memory catalog (tests).
  #
  # @return [AccessGrant::Catalog]
  def self.reset_catalog! = @catalog = Catalog.new

  # Replace the catalog by evaluating a DSL block (typically from
  # +config/access_grant/permissions.rb+).
  #
  # @yield DSL methods such as +resource+, +action+, +category+, +permission+
  # @return [void]
  # @see AccessGrant::Catalog::DSL
  def self.permissions(&) = catalog.replace(&)

  # Grant the Owner role (single-tenant or with +tenant:+). Prefer
  # +tenant.grant_owner!(user)+ in multi-tenant apps.
  #
  # @param user [Object] host user record with +access_grant :user+
  # @param tenant [Object, nil] required when +tenant_class+ is set
  # @return [AccessGrant::Role] the Owner role
  # @raise [AccessGrant::Error] when Owner is +:none+ or tenant args are wrong
  def self.grant_owner!(user, tenant: nil)
    Owner.grant_owner!(user, tenant: tenant)
  end

  # Revoke the Owner role from +user+. Fails if this would remove the last
  # Owner assignment for the scope.
  #
  # @param user [Object]
  # @param tenant [Object, nil]
  # @return [void]
  # @raise [AccessGrant::Error]
  def self.revoke_owner!(user, tenant: nil)
    Owner.revoke_owner!(user, tenant: tenant)
  end

  # Sync model +table_name+ values and optional +Role.belongs_to :tenant+
  # from the current {#config}. Called automatically from {#configure}.
  #
  # @return [void]
  def self.apply_configuration!
    Permission.table_name = config.tables.fetch(:permissions)
    Role.table_name = config.tables.fetch(:roles)
    RolePermission.table_name = config.tables.fetch(:role_permissions)

    tenant_class = config.tenant_class

    if tenant_class.nil? || tenant_class.to_s.empty?
      Role._reflections.delete(:tenant)
      Role.clear_reflections_cache
    else
      Role.belongs_to :tenant,
                      class_name: tenant_class.to_s,
                      foreign_key: :tenant_id,
                      optional: true,
                      inverse_of: :roles
    end
  end
end

require_relative "access_grant/models/permission"
require_relative "access_grant/models/role_permission"
require_relative "access_grant/models/role"

require_relative "access_grant/railtie" if defined?(Rails::Railtie)
