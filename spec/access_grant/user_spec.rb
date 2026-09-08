# frozen_string_literal: true

RSpec.describe "access_grant :user" do
  def create_permission!(key)
    AccessGrant::Permission.create!(key: key)
  end

  def create_role!(name:, tenant: nil, keys: [])
    role = AccessGrant::Role.create!(name: name, tenant_id: tenant&.id)
    role.permission_keys = keys if keys.any?
    role
  end

  before do
    AccessGrant.reset_config!
  end

  after { AccessGrant.reset_config! }

  describe "#permitted?" do
    context "when multi-tenant" do
      before do
        AccessGrant.configure do |config|
          config.tenant_class = "Organization"
        end
      end

      it "raises when tenant is missing" do
        create_permission!("invoices.index")
        user = User.create!

        expect do
          user.permitted?("invoices.index")
        end.to raise_error(AccessGrant::Error)
      end

      it "raises for a malformed key" do
        user = User.create!
        org = Organization.create!

        expect do
          user.permitted?("bad", tenant: org)
        end.to raise_error(AccessGrant::Error)
      end

      it "raises for an unknown well-formed key" do
        user = User.create!
        org = Organization.create!

        expect do
          user.permitted?("invoices.index", tenant: org)
        end.to raise_error(AccessGrant::Error)
      end

      it "returns true when a role for that tenant grants the key" do
        create_permission!("invoices.index")
        acme = Organization.create!
        beta = Organization.create!
        user = User.create!
        role = create_role!(name: "Viewer", tenant: acme, keys: %w[invoices.index])
        user.roles << role

        expect(user.permitted?("invoices.index", tenant: acme)).to be(true)
        expect(user.permitted?("invoices.index", tenant: beta)).to be(false)
      end

      it "unions permissions across multiple roles for the tenant" do
        create_permission!("invoices.index")
        create_permission!("invoices.update")
        acme = Organization.create!
        user = User.create!
        viewer = create_role!(name: "Viewer", tenant: acme, keys: %w[invoices.index])
        editor = create_role!(name: "Editor", tenant: acme, keys: %w[invoices.update])
        user.roles << viewer << editor

        expect(user.permitted?("invoices.index", tenant: acme)).to be(true)
        expect(user.permitted?("invoices.update", tenant: acme)).to be(true)
      end
    end

    context "when single-tenant" do
      before do
        AccessGrant.configure do |config|
          config.tenant_class = nil
        end
      end

      it "raises when tenant is supplied" do
        create_permission!("invoices.index")
        user = User.create!
        org = Organization.create!

        expect do
          user.permitted?("invoices.index", tenant: org)
        end.to raise_error(AccessGrant::Error)
      end

      it "returns true when a global role grants the key" do
        create_permission!("invoices.index")
        user = User.create!
        role = create_role!(name: "Viewer", keys: %w[invoices.index])
        user.roles << role

        expect(user.permitted?("invoices.index")).to be(true)
      end

      it "returns false when the user has no granting role" do
        create_permission!("invoices.index")
        user = User.create!

        expect(user.permitted?("invoices.index")).to be(false)
      end
    end
  end
end
