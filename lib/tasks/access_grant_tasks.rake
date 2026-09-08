# frozen_string_literal: true

namespace :access_grant do
  # Sync {AccessGrant.catalog} into the permissions table. Never deletes keys.
  # For :protected/:both, reattaches all keys to Owner roles.
  # Run on every deploy after migrate.
  desc "Upsert catalog permissions into the database (never deletes)"
  task sync_permissions: :environment do
    AccessGrant::Sync.call
  end

  # Ops recovery: ROLE=Owner USER_ID=1 TENANT_ID=42 rake access_grant:grant_role
  # Uses config.recover_access when set, else AccessGrant::Recovery.grant_role!.
  desc "Grant a named role to a user (ops lockout recovery). Env: ROLE, USER_ID, optional TENANT_ID"
  task grant_role: :environment do
    role_name = ENV.fetch("ROLE") { raise "ROLE is required" }
    user_id = Integer(ENV.fetch("USER_ID") { raise "USER_ID is required" })
    tenant_id = ENV["TENANT_ID"]&.then { |id| Integer(id) }

    callable = AccessGrant.config.recover_access
    if callable
      callable.call(role_name: role_name, user_id: user_id, tenant_id: tenant_id)
    else
      AccessGrant::Recovery.grant_role!(role_name: role_name, user_id: user_id, tenant_id: tenant_id)
    end
  end
end
