# frozen_string_literal: true

module AccessGrant
  # Join between {Role} and {Permission}.
  class RolePermission < ActiveRecord::Base
    self.table_name = AccessGrant.config.tables.fetch(:role_permissions)

    belongs_to :role, class_name: "AccessGrant::Role"
    belongs_to :permission, class_name: "AccessGrant::Permission"
  end
end
