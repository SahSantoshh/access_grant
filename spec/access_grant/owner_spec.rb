# frozen_string_literal: true

RSpec.describe "Owner API" do
  def create_permission!(key)
    AccessGrant::Permission.create!(key: key)
  end

  def configure_multi!(owner_role: :protected)
    AccessGrant.configure do |config|
      config.tenant_class = "Organization"
      config.user_class = "User"
      config.owner_role = owner_role
      config.owner_role_name = "Owner"
    end
  end

  def configure_single!(owner_role: :protected)
    AccessGrant.configure do |config|
      config.tenant_class = nil
      config.user_class = "User"
      config.owner_role = owner_role
      config.owner_role_name = "Owner"
    end
  end

  before { AccessGrant.reset_config! }
  after { AccessGrant.reset_config! }

  describe "access_grant :tenant" do
    it "associates roles to the tenant" do
      configure_multi!
      org = Organization.create!
      role = AccessGrant::Role.create!(name: "Viewer", tenant_id: org.id)

      expect(org.roles).to include(role)
    end

    it "invokes on_tenant_created after create when configured" do
      seen = nil
      AccessGrant.configure do |config|
        config.tenant_class = "Organization"
        config.on_tenant_created = ->(tenant) { seen = tenant }
      end

      org = Organization.create!
      expect(seen).to eq(org)
    end

    it "does not invoke on_tenant_created when unset" do
      configure_multi!
      expect { Organization.create! }.not_to raise_error
    end
  end

  describe "grant_owner!" do
    it "raises when owner_role is :none" do
      configure_multi!(owner_role: :none)
      org = Organization.create!
      user = User.create!

      expect do
        org.grant_owner!(user)
      end.to raise_error(AccessGrant::Error)
    end

    it "creates Owner with all permission keys in :protected mode" do
      configure_multi!(owner_role: :protected)
      create_permission!("invoices.index")
      create_permission!("invoices.update")
      org = Organization.create!
      user = User.create!

      org.grant_owner!(user)

      owner = org.roles.find { |r| r.name.casecmp("Owner").zero? }
      expect(owner).to be_present
      expect(owner.permission_keys).to match_array(%w[invoices.index invoices.update])
      expect(user.roles).to include(owner)
      expect(user.permitted?("invoices.index", tenant: org)).to be(true)
    end

    it "allows multiple owners on the same tenant" do
      configure_multi!(owner_role: :protected)
      create_permission!("invoices.index")
      org = Organization.create!
      maya = User.create!
      jordan = User.create!

      org.grant_owner!(maya)
      org.grant_owner!(jordan)

      owner = org.roles.find { |r| r.name.casecmp("Owner").zero? }
      expect(maya.roles).to include(owner)
      expect(jordan.roles).to include(owner)
    end

    it "creates Owner with empty permissions in :bypass mode and short-circuits permitted?" do
      configure_multi!(owner_role: :bypass)
      create_permission!("invoices.index")
      org = Organization.create!
      user = User.create!

      org.grant_owner!(user)

      owner = org.roles.find { |r| r.name.casecmp("Owner").zero? }
      expect(owner.permission_keys).to eq([])
      expect(user.permitted?("invoices.index", tenant: org)).to be(true)
    end

    it "still raises on unknown keys under :bypass" do
      configure_multi!(owner_role: :bypass)
      org = Organization.create!
      user = User.create!
      org.grant_owner!(user)

      expect do
        user.permitted?("invoices.index", tenant: org)
      end.to raise_error(AccessGrant::Error)
    end

    it "short-circuits permitted? in :both mode and attaches all keys" do
      configure_multi!(owner_role: :both)
      create_permission!("invoices.index")
      org = Organization.create!
      user = User.create!

      org.grant_owner!(user)

      owner = org.roles.find { |r| r.name.casecmp("Owner").zero? }
      expect(owner.permission_keys).to eq(%w[invoices.index])
      expect(user.permitted?("invoices.index", tenant: org)).to be(true)
    end

    it "does not short-circuit in :protected mode without the key on another path" do
      configure_multi!(owner_role: :protected)
      create_permission!("invoices.index")
      org = Organization.create!
      user = User.create!
      org.grant_owner!(user)

      owner = org.roles.find { |r| r.name.casecmp("Owner").zero? }
      AccessGrant::RolePermission.where(role_id: owner.id).delete_all

      expect(user.permitted?("invoices.index", tenant: org)).to be(false)
    end

    it "grants via AccessGrant.grant_owner! in single-tenant mode" do
      configure_single!(owner_role: :protected)
      create_permission!("invoices.index")
      user = User.create!

      AccessGrant.grant_owner!(user)

      owner = AccessGrant::Role.find_by("LOWER(name) = ?", "owner")
      expect(owner.tenant_id).to be_nil
      expect(owner.permission_keys).to eq(%w[invoices.index])
      expect(user.permitted?("invoices.index")).to be(true)
    end
  end

  describe "revoke_owner!" do
    it "removes a non-last Owner" do
      configure_multi!(owner_role: :protected)
      create_permission!("invoices.index")
      org = Organization.create!
      maya = User.create!
      jordan = User.create!
      org.grant_owner!(maya)
      org.grant_owner!(jordan)

      org.revoke_owner!(maya)

      owner = org.roles.find { |r| r.name.casecmp("Owner").zero? }
      expect(maya.roles).not_to include(owner)
      expect(jordan.roles).to include(owner)
    end

    it "raises when revoking the last Owner" do
      configure_multi!(owner_role: :bypass)
      create_permission!("invoices.index")
      org = Organization.create!
      user = User.create!
      org.grant_owner!(user)

      expect do
        org.revoke_owner!(user)
      end.to raise_error(AccessGrant::Error)

      owner = org.roles.find { |r| r.name.casecmp("Owner").zero? }
      expect(user.roles.reload).to include(owner)
    end

    it "raises when HABTM delete would remove the last Owner assignment" do
      configure_multi!(owner_role: :protected)
      create_permission!("invoices.index")
      org = Organization.create!
      user = User.create!
      org.grant_owner!(user)
      owner = org.roles.find { |r| r.name.casecmp("Owner").zero? }

      expect do
        user.roles.delete(owner)
      end.to raise_error(AccessGrant::Error)

      expect(user.roles.reload).to include(owner)
    end
  end

  describe "protected Owner role" do
    before do
      configure_multi!(owner_role: :protected)
      create_permission!("invoices.index")
      create_permission!("invoices.update")
      @org = Organization.create!
      @user = User.create!
      @org.grant_owner!(@user)
      @owner = @org.roles.find { |r| r.name.casecmp("Owner").zero? }
    end

    it "blocks destroy of the Owner role" do
      expect do
        @owner.destroy!
      end.to raise_error(ActiveRecord::RecordNotDestroyed)

      expect(AccessGrant::Role.exists?(@owner.id)).to be(true)
    end

    it "allows tenant destroy to cascade through protected Owner" do
      owner_id = @owner.id

      expect { @org.destroy! }.not_to raise_error

      expect(Organization.exists?(@org.id)).to be(false)
      expect(AccessGrant::Role.exists?(owner_id)).to be(false)
    end

    it "blocks public permission_keys= on the Owner role" do
      expect do
        @owner.permission_keys = %w[invoices.index]
      end.to raise_error(AccessGrant::Error)

      expect(@owner.reload.permission_keys).to match_array(%w[invoices.index invoices.update])
    end

    it "blocks permission association remove on the Owner role" do
      permission = AccessGrant::Permission.find_by!(key: "invoices.update")

      expect do
        @owner.permissions.delete(permission)
      end.to raise_error(AccessGrant::Error)

      expect(@owner.reload.permission_keys).to match_array(%w[invoices.index invoices.update])
    end

    it "blocks permission association add on the Owner role" do
      create_permission!("invoices.destroy")
      permission = AccessGrant::Permission.find_by!(key: "invoices.destroy")

      expect do
        @owner.permissions << permission
      end.to raise_error(AccessGrant::Error)

      expect(@owner.reload.permission_keys).to match_array(%w[invoices.index invoices.update])
    end

    it "allows Sync.call to reattach Owner keys" do
      AccessGrant::RolePermission.where(role_id: @owner.id).delete_all
      expect(@owner.reload.permission_keys).to eq([])

      AccessGrant.permissions do
        category "invoices" do
          permission "invoices.index", "list"
          permission "invoices.update", "update"
        end
      end
      AccessGrant::Sync.call

      expect(@owner.reload.permission_keys).to match_array(%w[invoices.index invoices.update])
    end

    it "does not expose replace_permission_keys! publicly" do
      expect(@owner).not_to respond_to(:replace_permission_keys!)
    end

    it "does not expose Sync.replace_role_permissions! publicly" do
      expect(AccessGrant::Sync).not_to respond_to(:replace_role_permissions!)
    end
  end

  describe "reserved Owner name" do
    it "rejects ordinary Role create with the Owner name when Owner is enabled" do
      configure_multi!(owner_role: :protected)
      org = Organization.create!

      role = AccessGrant::Role.new(name: "Owner", tenant_id: org.id)
      expect(role).not_to be_valid
      expect(role.errors[:name]).to be_present
    end

    it "rejects forging Owner via a public owner_managed flag" do
      configure_multi!(owner_role: :protected)
      org = Organization.create!
      role = AccessGrant::Role.new(name: "Owner", tenant_id: org.id)

      expect(role).not_to respond_to(:owner_managed=)
      expect(role).not_to be_valid
    end

    it "rejects case-insensitive rename to Owner name" do
      configure_multi!(owner_role: :protected)
      org = Organization.create!
      role = AccessGrant::Role.create!(name: "Viewer", tenant_id: org.id)

      role.name = "owner"
      expect(role).not_to be_valid
    end

    it "allows the Owner name when owner_role is :none" do
      configure_multi!(owner_role: :none)
      org = Organization.create!

      role = AccessGrant::Role.new(name: "Owner", tenant_id: org.id)
      expect(role).to be_valid
    end

    it "does not expose with_owner_role_creation publicly" do
      expect(AccessGrant::Owner).not_to respond_to(:with_owner_role_creation)
    end

    it "creates Owner roles via grant_owner! despite reserved name" do
      configure_multi!(owner_role: :protected)
      org = Organization.create!
      user = User.create!

      org.grant_owner!(user)

      owner = org.roles.find { |r| r.name.casecmp("Owner").zero? }
      expect(owner).to be_persisted
    end
  end
end
