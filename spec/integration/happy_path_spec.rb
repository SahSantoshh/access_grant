# frozen_string_literal: true

# Covered scenarios exercised (subset of docs/superpowers/specs/2026-09-07-usage-scenarios.md):
#   S014 — sync idempotence (upsert, stable key count, description updates)
#   S023 — ordinary tenant role + permission assignment at runtime
#   S043 — permitted? true for granted key in that tenant
#   S044 — same user denied in another tenant (no role / cross-tenant)
#   S088 — grant_owner! creates protected Owner with all keys
#   S089 — second owner allowed; revoke of non-last succeeds
#   S090 — revoke of last Owner raises
# Optional: bypass Owner short-circuit (separate example)

RSpec.describe "AccessGrant happy path (multi-tenant smoke)" do
  before do
    AccessGrant.reset_config!
    AccessGrant.reset_catalog!
    AccessGrant.configure do |config|
      config.tenant_class = "Organization"
      config.user_class = "User"
      config.owner_role = :protected
      config.owner_role_name = "Owner"
    end
  end

  after { AccessGrant.reset_config! }

  it "syncs catalog, grants ordinary and Owner roles, and scopes permitted? by tenant" do
    AccessGrant.permissions do
      category "invoices" do
        permission "invoices.index", "List invoices"
        permission "invoices.show", "Show invoice"
      end
    end

    AccessGrant::Sync.call
    expect(AccessGrant::Permission.count).to eq(2)

    AccessGrant.permissions do
      category "invoices" do
        permission "invoices.index", "Can view list of invoices"
        permission "invoices.show", "Can view an invoice"
      end
    end
    AccessGrant::Sync.call

    expect(AccessGrant::Permission.count).to eq(2)
    expect(AccessGrant::Permission.find_by!(key: "invoices.index").description)
      .to eq("Can view list of invoices")

    acme = Organization.create!
    beta = Organization.create!
    maya = User.create!
    jordan = User.create!

    viewer = AccessGrant::Role.create!(name: "Viewer", tenant_id: acme.id)
    viewer.permission_keys = %w[invoices.index]
    maya.roles << viewer

    expect(maya.permitted?("invoices.index", tenant: acme)).to be(true)
    expect(maya.permitted?("invoices.index", tenant: beta)).to be(false)

    acme.grant_owner!(maya)
    owner = acme.roles.find { |r| r.name.casecmp("Owner").zero? }
    expect(owner).to be_present
    expect(owner.permission_keys).to match_array(%w[invoices.index invoices.show])
    expect(maya.permitted?("invoices.show", tenant: acme)).to be(true)
    expect(maya.permitted?("invoices.show", tenant: beta)).to be(false)

    acme.grant_owner!(jordan)
    expect(jordan.roles).to include(owner)
    expect(jordan.permitted?("invoices.index", tenant: acme)).to be(true)

    acme.revoke_owner!(maya)
    expect(maya.roles.reload).not_to include(owner)
    expect(jordan.roles.reload).to include(owner)

    expect do
      acme.revoke_owner!(jordan)
    end.to raise_error(AccessGrant::Error)
    expect(jordan.roles.reload).to include(owner)
  end

  it "short-circuits permitted? for bypass Owner without attaching keys" do
    AccessGrant.configure do |config|
      config.tenant_class = "Organization"
      config.user_class = "User"
      config.owner_role = :bypass
      config.owner_role_name = "Owner"
    end

    AccessGrant::Permission.create!(key: "invoices.index", description: "list", category: "invoices")
    org = Organization.create!
    user = User.create!

    org.grant_owner!(user)
    owner = org.roles.find { |r| r.name.casecmp("Owner").zero? }

    expect(owner.permission_keys).to eq([])
    expect(user.permitted?("invoices.index", tenant: org)).to be(true)
  end
end
