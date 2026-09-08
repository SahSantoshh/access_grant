# frozen_string_literal: true

module AccessGrant
  # Mixed into the host user model via +access_grant :user+.
  #
  # Provides HABTM +:roles+ and {#permitted?}.
  module User
    # @api private
    def self.included(base)
      configure_roles_association(base)
      base.class_eval do
        private

        def access_grant_ensure_can_remove_role(role)
          AccessGrant::Owner.ensure_can_remove_assignment!(role)
        end
      end
    end

    def self.configure_roles_association(base)
      base.has_and_belongs_to_many :roles,
                                   class_name: "AccessGrant::Role",
                                   join_table: AccessGrant.config.tables.fetch(:user_roles),
                                   foreign_key: :user_id,
                                   association_foreign_key: :role_id,
                                   before_remove: :access_grant_ensure_can_remove_role
    end
    private_class_method :configure_roles_association

    # Capability check: does this user have +key+ via any role in scope?
    #
    # Multi-tenant (+tenant_class+ set): +tenant:+ is required.
    # Single-tenant: omit +tenant:+ (raises if supplied).
    #
    # Unknown or malformed keys raise in all Owner modes (including bypass).
    # With +:bypass+ / +:both+, having the Owner role short-circuits to +true+
    # after the key is validated.
    #
    # @param key [String, Symbol] +resource.action+
    # @param tenant [Object, nil] tenant record responding to +id+
    # @return [Boolean]
    # @raise [AccessGrant::Error] malformed key, unknown key, or bad tenant args
    def permitted?(key, tenant: nil)
      normalized = PermissionKey.normalize!(key)

      raise Error, "Unknown permission key: #{normalized.inspect}" unless Permission.exists?(key: normalized)

      scoped_roles = roles_for_tenant(tenant)
      return true if owner_bypass?(scoped_roles)

      scoped_roles.joins(:permissions).merge(Permission.where(key: normalized)).exists?
    end

    private

    def roles_for_tenant(tenant)
      if multi_tenant?
        raise Error, "tenant: is required in multi-tenant mode" if tenant.nil?

        roles.where(tenant_id: tenant.id)
      else
        raise Error, "tenant: must not be supplied in single-tenant mode" unless tenant.nil?

        roles.where(tenant_id: nil)
      end
    end

    def owner_bypass?(scoped_roles)
      mode = AccessGrant.config.owner_role
      return false unless %i[bypass both].include?(mode)

      owner_name = AccessGrant.config.owner_role_name.to_s
      scoped_roles.where("LOWER(name) = ?", owner_name.downcase).exists?
    end

    def multi_tenant?
      tenant_class = AccessGrant.config.tenant_class
      !(tenant_class.nil? || tenant_class.to_s.empty?)
    end
  end

  # Extends +ActiveRecord::Base+ with {#access_grant}.
  module ModelDsl
    # Declare participation in AccessGrant.
    #
    # @param role [Symbol] +:user+ or +:tenant+
    # @return [void]
    # @raise [ArgumentError]
    def access_grant(role)
      case role
      when :user
        include AccessGrant::User
      when :tenant
        include AccessGrant::Tenant
      else
        raise ArgumentError, "Unknown access_grant role: #{role.inspect}"
      end
    end
  end
end

ActiveRecord::Base.extend(AccessGrant::ModelDsl)
