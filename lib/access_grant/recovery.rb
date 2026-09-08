# frozen_string_literal: true

module AccessGrant
  # Ops lockout recovery used by +rake access_grant:grant_role+.
  #
  # Override via {AccessGrant::Configuration#recover_access}.
  module Recovery
    module_function

    # Grant a named role (or Owner) to a user by id.
    #
    # When +role_name+ matches {AccessGrant::Configuration#owner_role_name}
    # (case-insensitive) and Owner is enabled, delegates to
    # {AccessGrant::Owner.grant_owner!}.
    #
    # @param role_name [String, Symbol]
    # @param user_id [Integer]
    # @param tenant_id [Integer, nil] required in multi-tenant mode
    # @return [AccessGrant::Role]
    # @raise [AccessGrant::Error]
    def grant_role!(role_name:, user_id:, tenant_id: nil)
      user = user_class.find(user_id)

      if owner_role_request?(role_name)
        tenant = resolve_tenant_for_owner!(tenant_id)
        return Owner.grant_owner!(user, tenant: tenant)
      end

      ensure_tenant_id_for_role!(tenant_id)
      role = find_role!(role_name, tenant_id: tenant_id)
      user.roles << role unless user.roles.exists?(id: role.id)
      role
    end

    def owner_role_request?(role_name)
      return false if AccessGrant.config.owner_role == :none

      role_name.to_s.casecmp?(AccessGrant.config.owner_role_name.to_s)
    end
    private_class_method :owner_role_request?

    def user_class
      AccessGrant.config.user_class.constantize
    end
    private_class_method :user_class

    def resolve_tenant_for_owner!(tenant_id)
      if multi_tenant?
        raise Error, "tenant_id is required in multi-tenant mode" if tenant_id.nil?

        tenant_class.find(tenant_id)
      else
        raise Error, "tenant_id must not be supplied in single-tenant mode" unless tenant_id.nil?

        nil
      end
    end
    private_class_method :resolve_tenant_for_owner!

    def ensure_tenant_id_for_role!(tenant_id)
      if multi_tenant?
        raise Error, "tenant_id is required in multi-tenant mode" if tenant_id.nil?
      else
        raise Error, "tenant_id must not be supplied in single-tenant mode" unless tenant_id.nil?
      end
    end
    private_class_method :ensure_tenant_id_for_role!

    def find_role!(role_name, tenant_id:)
      role = Role.where(tenant_id: tenant_id)
                 .where("LOWER(name) = ?", role_name.to_s.downcase)
                 .first
      raise Error, "Role not found: #{role_name.inspect}" unless role

      role
    end
    private_class_method :find_role!

    def multi_tenant?
      tenant_class_name = AccessGrant.config.tenant_class
      !(tenant_class_name.nil? || tenant_class_name.to_s.empty?)
    end
    private_class_method :multi_tenant?

    def tenant_class
      AccessGrant.config.tenant_class.constantize
    end
    private_class_method :tenant_class
  end
end
