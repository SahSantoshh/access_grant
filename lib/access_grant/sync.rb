# frozen_string_literal: true

module AccessGrant
  # Upserts the in-memory catalog into the permissions table.
  #
  # Never deletes orphaned DB keys. For +:protected+ / +:both+, re-attaches
  # every permission key to Owner-named roles.
  #
  # Invoked by +rake access_grant:sync_permissions+.
  class Sync
    # @api private
    REATTACH_OWNER_MODES = %i[protected both].freeze

    # Persist catalog entries (description/category) and optionally reattach
    # Owner permissions.
    #
    # @param catalog [AccessGrant::Catalog]
    # @return [void]
    def self.call(catalog: AccessGrant.catalog)
      ActiveRecord::Base.transaction do
        catalog.entries.each do |entry|
          permission = Permission.find_or_initialize_by(key: entry.fetch(:key))
          permission.description = entry[:description]
          permission.category = entry[:category]
          permission.save!
        end

        reattach_owner_permissions! if reattach_owner?
      end
    end

    # @api private
    def self.replace_role_permissions!(role, keys)
      normalized = Array(keys).map { |key| PermissionKey.normalize!(key) }

      Role.transaction do
        resolved = normalized.map do |key|
          Permission.find_by(key: key) ||
            raise(Error, "Unknown permission key: #{key.inspect}")
        end

        role.role_permissions.delete_all
        resolved.each do |permission|
          RolePermission.create!(role_id: role.id, permission_id: permission.id)
        end
      end
    end
    private_class_method :replace_role_permissions!

    def self.reattach_owner?
      REATTACH_OWNER_MODES.include?(AccessGrant.config.owner_role)
    end
    private_class_method :reattach_owner?

    def self.reattach_owner_permissions!
      owner_name = AccessGrant.config.owner_role_name.to_s
      keys = Permission.pluck(:key)

      Role.where("LOWER(name) = ?", owner_name.downcase).find_each do |role|
        replace_role_permissions!(role, keys)
      end
    end
    private_class_method :reattach_owner_permissions!
  end
end
