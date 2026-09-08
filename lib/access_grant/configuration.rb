# frozen_string_literal: true

module AccessGrant
  # Host-facing settings for AccessGrant. Set via {AccessGrant.configure}.
  #
  # Defaults match the architecture configuration reference; the setup
  # generator writes a fully commented initializer covering every option.
  class Configuration
    # @return [String, nil] Host tenant model (e.g. +"Organization"+); +nil+ = single-tenant
    attr_accessor :tenant_class

    # @return [String] Host user model that receives roles (default: +"User"+)
    attr_accessor :user_class

    # @return [Symbol] Owner mechanism: +:protected+, +:bypass+, +:both+, or +:none+ (default: +:protected+)
    attr_accessor :owner_role

    # @return [String] Reserved Owner role name, case-insensitive (default: +"Owner"+)
    attr_accessor :owner_role_name

    # @return [Hash{Symbol=>String}] Physical table names (+:roles+, +:permissions+, +:role_permissions+, +:user_roles+)
    attr_accessor :tables

    # @return [Array<String>] Actions emitted for each catalog +resource+ (default: CRUD + index/show)
    attr_accessor :default_permission_actions

    # @return [Symbol] Controller method for the acting user (default: +:current_user+)
    attr_accessor :current_user_method

    # @return [Symbol] Controller method for the tenant in multi-tenant mode (default: +:current_tenant+)
    attr_accessor :current_tenant_method

    # @return [Proc, nil] Called after tenant create; seed default roles (not Owner assignment)
    attr_accessor :on_tenant_created

    # @return [Proc, nil] Ops lockout recovery; +nil+ uses {AccessGrant::Recovery.grant_role!}
    attr_accessor :recover_access

    # Build a configuration with architecture defaults.
    def initialize
      @user_class = "User"
      @owner_role = :protected
      @owner_role_name = "Owner"
      @default_permission_actions = %w[index show create update destroy]
      @current_user_method = :current_user
      @current_tenant_method = :current_tenant
      @tables = {
        roles: "roles",
        permissions: "permissions",
        role_permissions: "role_permissions",
        user_roles: "user_roles"
      }
    end
  end
end
