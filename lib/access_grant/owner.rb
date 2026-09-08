# frozen_string_literal: true

module AccessGrant
  # Owner role grant/revoke and last-Owner assignment guards.
  #
  # Prefer +tenant.grant_owner!(user)+ / +tenant.revoke_owner!(user)+ when
  # multi-tenant; use {AccessGrant.grant_owner!} in single-tenant mode.
  module Owner
    # @api private
    OWNER_ROLE_CREATION_KEY = :access_grant_owner_role_creation

    module_function

    # @api private
    def with_owner_role_creation
      previous = Thread.current[OWNER_ROLE_CREATION_KEY]
      Thread.current[OWNER_ROLE_CREATION_KEY] = true
      yield
    ensure
      Thread.current[OWNER_ROLE_CREATION_KEY] = previous
    end
    private_class_method :with_owner_role_creation

    # @api private
    def owner_role_creation?
      Thread.current[OWNER_ROLE_CREATION_KEY] == true
    end
    private_class_method :owner_role_creation?

    # Find or create the Owner role for the scope, attach catalog keys when
    # mode is +:protected+ / +:both+, and assign +user+.
    #
    # @param user [Object] host user with +access_grant :user+
    # @param tenant [Object, nil] required in multi-tenant mode
    # @return [AccessGrant::Role]
    # @raise [AccessGrant::Error]
    def grant_owner!(user, tenant: nil)
      ensure_owner_enabled!
      ensure_tenant_arg!(tenant)

      role = find_or_create_owner_role!(tenant_id_for(tenant))
      attach_owner_permissions!(role) if attach_owner_permissions?

      user.roles << role unless user.roles.exists?(id: role.id)
      role
    end

    # Remove Owner from +user+. Raises if this is the last Owner assignment
    # for the scope (also enforced on HABTM +roles.delete+).
    #
    # @param user [Object]
    # @param tenant [Object, nil]
    # @return [void]
    # @raise [AccessGrant::Error]
    def revoke_owner!(user, tenant: nil)
      ensure_owner_enabled!
      ensure_tenant_arg!(tenant)

      role = find_owner_role(tenant_id_for(tenant))
      return unless role && user.roles.exists?(id: role.id)

      Role.transaction do
        user.roles.delete(role)
      end
    end

    # Guard used by HABTM +before_remove+ and revoke paths.
    #
    # @param role [AccessGrant::Role]
    # @return [void]
    # @raise [AccessGrant::Error] when removing the last Owner assignment
    def ensure_can_remove_assignment!(role)
      return if AccessGrant.config.owner_role == :none
      return unless role.owner_named?

      role.lock!
      return if assignment_count(role) > 1

      raise Error, "Cannot revoke the last Owner for this scope"
    end

    def ensure_owner_enabled!
      return unless AccessGrant.config.owner_role == :none

      raise Error, "Owner is disabled (owner_role: :none)"
    end
    private_class_method :ensure_owner_enabled!

    def ensure_tenant_arg!(tenant)
      if multi_tenant?
        raise Error, "tenant: is required in multi-tenant mode" if tenant.nil?
      else
        raise Error, "tenant: must not be supplied in single-tenant mode" unless tenant.nil?
      end
    end
    private_class_method :ensure_tenant_arg!

    def tenant_id_for(tenant)
      tenant&.id
    end
    private_class_method :tenant_id_for

    def multi_tenant?
      tenant_class = AccessGrant.config.tenant_class
      !(tenant_class.nil? || tenant_class.to_s.empty?)
    end
    private_class_method :multi_tenant?

    def attach_owner_permissions?
      %i[protected both].include?(AccessGrant.config.owner_role)
    end
    private_class_method :attach_owner_permissions?

    def attach_owner_permissions!(role)
      Sync.__send__(:replace_role_permissions!, role, Permission.pluck(:key))
    end
    private_class_method :attach_owner_permissions!

    def find_or_create_owner_role!(tenant_id)
      existing = find_owner_role(tenant_id)
      return existing if existing

      with_owner_role_creation do
        Role.create!(name: AccessGrant.config.owner_role_name.to_s, tenant_id: tenant_id)
      end
    end
    private_class_method :find_or_create_owner_role!

    def find_owner_role(tenant_id)
      owner_name = AccessGrant.config.owner_role_name.to_s
      Role.where(tenant_id: tenant_id).where("LOWER(name) = ?", owner_name.downcase).first
    end
    private_class_method :find_owner_role

    def assignment_count(role)
      join_table = AccessGrant.config.tables.fetch(:user_roles)
      sql = ActiveRecord::Base.sanitize_sql_array(
        ["SELECT COUNT(*) FROM #{join_table} WHERE role_id = ?", role.id]
      )
      ActiveRecord::Base.connection.select_value(sql).to_i
    end
    private_class_method :assignment_count
  end
end
