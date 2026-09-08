# frozen_string_literal: true

module AccessGrant
  # Catalog permission row (+key+, +description+, +category+).
  #
  # Metadata is owned by sync/code; admins select keys but do not invent them.
  class Permission < ActiveRecord::Base
    self.table_name = AccessGrant.config.tables.fetch(:permissions)

    validates :key, presence: true, uniqueness: true
    validate :key_must_be_valid_permission_key

    # Permissions for one model/controller grouping label (default = resource
    # name, e.g. +"invoices"+). Uses index on +(category, key)+.
    #
    # @param category [String, Symbol]
    # @return [ActiveRecord::Relation]
    scope :by_category, lambda { |category|
      where(category: category.to_s).order(:key)
    }

    # Full catalog ordered for admin UIs (group by category, then key).
    #
    # @return [ActiveRecord::Relation]
    scope :ordered_for_ui, -> { order(:category, :key) }

    private

    def key_must_be_valid_permission_key
      return if key.blank?
      return if PermissionKey.valid?(key)

      errors.add(:key, "is invalid")
    end
  end
end
