# frozen_string_literal: true

module AccessGrant
  # Mixed into the host tenant model via +access_grant :tenant+.
  #
  # Provides +has_many :roles+, {#grant_owner!}, {#revoke_owner!}, and
  # optional {AccessGrant::Configuration#on_tenant_created} after create.
  module Tenant
    # @api private
    def self.included(base)
      base.has_many :roles,
                    class_name: "AccessGrant::Role",
                    foreign_key: :tenant_id,
                    dependent: :destroy,
                    inverse_of: :tenant

      base.after_create :access_grant_invoke_on_tenant_created
    end

    # Grant the Owner role for this tenant to +user+.
    #
    # @param user [Object] host user with +access_grant :user+
    # @return [AccessGrant::Role]
    # @raise [AccessGrant::Error]
    # @see AccessGrant::Owner.grant_owner!
    def grant_owner!(user)
      Owner.grant_owner!(user, tenant: self)
    end

    # Revoke Owner from +user+ for this tenant.
    #
    # @param user [Object]
    # @return [void]
    # @raise [AccessGrant::Error] last Owner cannot be revoked
    # @see AccessGrant::Owner.revoke_owner!
    def revoke_owner!(user)
      Owner.revoke_owner!(user, tenant: self)
    end

    private

    def access_grant_invoke_on_tenant_created
      callback = AccessGrant.config.on_tenant_created
      callback&.call(self)
    end
  end
end
