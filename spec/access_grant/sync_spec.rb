# frozen_string_literal: true

RSpec.describe AccessGrant::Sync do
  before do
    AccessGrant.reset_config!
    AccessGrant.reset_catalog!
  end

  after { AccessGrant.reset_config! }

  describe ".call" do
    it "upserts catalog entries and never deletes orphaned DB keys" do
      AccessGrant::Permission.create!(
        key: "legacy.orphan",
        description: "keep me",
        category: "legacy"
      )
      AccessGrant::Permission.create!(
        key: "invoices.index",
        description: "old description",
        category: "old"
      )

      AccessGrant.permissions do
        category "invoices" do
          permission "invoices.index", "Can view list of invoices"
          permission "invoices.show", "Can view an invoice"
        end
      end

      described_class.call

      expect(AccessGrant::Permission.pluck(:key)).to match_array(
        %w[legacy.orphan invoices.index invoices.show]
      )

      index = AccessGrant::Permission.find_by!(key: "invoices.index")
      expect(index.description).to eq("Can view list of invoices")
      expect(index.category).to eq("invoices")

      orphan = AccessGrant::Permission.find_by!(key: "legacy.orphan")
      expect(orphan.description).to eq("keep me")
      expect(orphan.category).to eq("legacy")
    end

    it "reattaches all Permission keys to Owner roles when owner_role is :protected" do
      AccessGrant.configure { |c| c.owner_role = :protected }

      AccessGrant::Permission.create!(key: "legacy.orphan")
      AccessGrant.permissions do
        category "invoices" do
          permission "invoices.index", "list"
        end
      end

      owner_a = AccessGrant::Owner.__send__(:with_owner_role_creation) do
        AccessGrant::Role.create!(name: "Owner", tenant_id: 1)
      end
      owner_b = AccessGrant::Owner.__send__(:with_owner_role_creation) do
        AccessGrant::Role.create!(name: "owner", tenant_id: 2)
      end
      viewer = AccessGrant::Role.create!(name: "Viewer", tenant_id: 1)

      AccessGrant::RolePermission.where(role_id: [owner_a.id, owner_b.id]).delete_all
      viewer.permission_keys = []

      described_class.call

      expect(owner_a.reload.permission_keys).to match_array(%w[legacy.orphan invoices.index])
      expect(owner_b.reload.permission_keys).to match_array(%w[legacy.orphan invoices.index])
      expect(viewer.reload.permission_keys).to eq([])
    end

    it "skips Owner reattach when owner_role is :bypass" do
      AccessGrant.configure { |c| c.owner_role = :bypass }

      AccessGrant.permissions do
        category "invoices" do
          permission "invoices.index", "list"
        end
      end

      owner = AccessGrant::Owner.__send__(:with_owner_role_creation) do
        AccessGrant::Role.create!(name: "Owner")
      end
      owner.permission_keys = []

      described_class.call

      expect(owner.reload.permission_keys).to eq([])
      expect(AccessGrant::Permission.find_by!(key: "invoices.index")).to be_present
    end
  end
end
