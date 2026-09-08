# frozen_string_literal: true

module AccessGrant
  # Named role within a tenant (or global when +tenant_id+ is +nil+).
  #
  # Assign permissions with {#permission_keys=}. Owner roles are reserved and
  # protected according to {AccessGrant::Configuration#owner_role}.
  class Role < ActiveRecord::Base
    self.table_name = AccessGrant.config.tables.fetch(:roles)

    has_many :role_permissions, class_name: "AccessGrant::RolePermission", dependent: :destroy,
                                inverse_of: :role,
                                before_add: :prevent_protected_owner_permission_change,
                                before_remove: :prevent_protected_owner_permission_change
    has_many :permissions, through: :role_permissions, class_name: "AccessGrant::Permission",
                           before_add: :prevent_protected_owner_permission_change,
                           before_remove: :prevent_protected_owner_permission_change

    validates :name, presence: true,
                     uniqueness: { scope: :tenant_id, case_sensitive: false }
    validate :name_not_reserved_owner
    before_destroy :prevent_protected_owner_destroy, prepend: true

    # @return [Array<String>] permission keys currently granted
    def permission_keys
      permissions.pluck(:key)
    end

    # Atomically replace the full permission set. Unknown/malformed keys raise
    # and leave the previous set intact.
    #
    # @param keys [Array<String, Symbol>]
    # @return [Array<AccessGrant::Permission>]
    # @raise [AccessGrant::Error] protected Owner, unknown key, or malformed key
    def permission_keys=(keys)
      raise Error, "Cannot modify permissions on protected Owner role" if protected_owner_role?

      normalized = Array(keys).map { |key| PermissionKey.normalize!(key) }

      transaction do
        resolved = normalized.map do |key|
          Permission.find_by(key: key) ||
            raise(Error, "Unknown permission key: #{key.inspect}")
        end

        self.permissions = resolved
      end
    end

    # @return [Boolean] true when this is the Owner role under +:protected+ / +:both+
    def protected_owner_role?
      return false unless %i[protected both].include?(AccessGrant.config.owner_role)

      owner_named?
    end

    # @return [Boolean] name matches configured Owner name (case-insensitive)
    def owner_named?
      name.to_s.downcase == AccessGrant.config.owner_role_name.to_s.downcase
    end

    # Create-only: for each name => permission keys, creates the role when missing
    # under +tenant+ (or +tenant_id+ nil when +tenant+ is nil) and assigns keys.
    # Existing roles are left unchanged.
    #
    # @param tenant [Object, nil] tenant record responding to +id+, or nil (single-tenant)
    # @param defaults [Hash] role name => array of permission key strings/symbols
    # @return [void]
    def self.ensure_defaults_for!(tenant, defaults)
      tenant_id = tenant&.id
      defaults.each do |role_name, keys|
        next if exists?(name: role_name.to_s, tenant_id: tenant_id)

        role = create!(name: role_name.to_s, tenant_id: tenant_id)
        role.permission_keys = keys
      end
    end

    private

    def name_not_reserved_owner
      return if Owner.__send__(:owner_role_creation?)
      return if AccessGrant.config.owner_role == :none
      return unless owner_named?

      errors.add(:name, "is reserved for the Owner role")
    end

    def prevent_protected_owner_destroy
      return unless protected_owner_role?
      return if destroyed_by_association # tenant/org cascading destroy

      errors.add(:base, "Cannot destroy protected Owner role")
      throw(:abort)
    end

    def prevent_protected_owner_permission_change(_record)
      return unless protected_owner_role?
      return if destroyed_by_association # tenant/org cascading destroy

      raise Error, "Cannot modify permissions on protected Owner role"
    end
  end
end
