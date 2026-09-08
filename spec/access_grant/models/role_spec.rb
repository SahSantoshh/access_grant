# frozen_string_literal: true

RSpec.describe AccessGrant::Role do
  def create_permission!(key)
    AccessGrant::Permission.create!(key: key)
  end

  it "uses the configured roles table name" do
    expect(described_class.table_name).to eq(AccessGrant.config.tables.fetch(:roles))
  end

  describe "#permission_keys=" do
    it "replaces the full permission set atomically" do
      create_permission!("invoices.index")
      create_permission!("invoices.update")
      role = described_class.create!(name: "Viewer")

      role.permission_keys = %w[invoices.index invoices.update]
      expect(role.permission_keys).to match_array(%w[invoices.index invoices.update])

      expect do
        role.permission_keys = %w[bad]
      end.to raise_error(AccessGrant::Error)

      expect(role.reload.permission_keys).to match_array(%w[invoices.index invoices.update])
    end

    it "rolls back when a key is unknown but well-formed" do
      create_permission!("invoices.index")
      role = described_class.create!(name: "Editor")
      role.permission_keys = %w[invoices.index]

      expect do
        role.permission_keys = %w[invoices.index invoices.destroy]
      end.to raise_error(AccessGrant::Error)

      expect(role.reload.permission_keys).to eq(%w[invoices.index])
    end
  end

  describe ".ensure_defaults_for!" do
    it "creates missing roles with permission keys and skips existing names" do
      create_permission!("invoices.index")
      create_permission!("invoices.update")
      described_class.create!(name: "Admin", tenant_id: 1)

      described_class.ensure_defaults_for!(
        Struct.new(:id).new(1),
        "Admin" => %w[invoices.index],
        "Member" => %w[invoices.index invoices.update]
      )

      expect(described_class.where(tenant_id: 1, name: "Admin").count).to eq(1)
      admin = described_class.find_by!(tenant_id: 1, name: "Admin")
      expect(admin.permission_keys).to eq([])

      member = described_class.find_by!(tenant_id: 1, name: "Member")
      expect(member.permission_keys).to match_array(%w[invoices.index invoices.update])
    end
  end

  describe ".ensure_resource_defaults_for!" do
    it "creates Viewer and Manager roles per permission category" do
      AccessGrant::Permission.create!(key: "invoices.index", category: "invoices")
      AccessGrant::Permission.create!(key: "invoices.show", category: "invoices")
      AccessGrant::Permission.create!(key: "invoices.destroy", category: "invoices")
      AccessGrant::Permission.create!(key: "billing.export", category: "billing")

      described_class.ensure_resource_defaults_for!(Struct.new(:id).new(7))

      viewer = described_class.find_by!(tenant_id: 7, name: "Invoices Viewer")
      expect(viewer.permission_keys).to match_array(%w[invoices.index invoices.show])

      manager = described_class.find_by!(tenant_id: 7, name: "Invoices Manager")
      expect(manager.permission_keys).to match_array(
        %w[invoices.index invoices.show invoices.destroy]
      )

      billing_manager = described_class.find_by!(tenant_id: 7, name: "Billing Manager")
      expect(billing_manager.permission_keys).to eq(%w[billing.export])
      expect(described_class.find_by(tenant_id: 7, name: "Billing Viewer")).to be_nil
    end

    it "is create-only for existing role names" do
      AccessGrant::Permission.create!(key: "invoices.index", category: "invoices")
      AccessGrant::Permission.create!(key: "invoices.show", category: "invoices")
      described_class.create!(name: "Invoices Viewer", tenant_id: 7)

      described_class.ensure_resource_defaults_for!(Struct.new(:id).new(7))

      expect(described_class.find_by!(tenant_id: 7, name: "Invoices Viewer").permission_keys).to eq([])
      expect(described_class.find_by!(tenant_id: 7, name: "Invoices Manager").permission_keys)
        .to match_array(%w[invoices.index invoices.show])
    end
  end

  describe "name uniqueness" do
    it "rejects a case-insensitive duplicate within the same tenant_id" do
      described_class.create!(name: "Viewer", tenant_id: 1)
      duplicate = described_class.new(name: "viewer", tenant_id: 1)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to be_present
    end

    it "rejects a case-insensitive duplicate when tenant_id is nil" do
      described_class.create!(name: "Viewer", tenant_id: nil)
      duplicate = described_class.new(name: "VIEWER", tenant_id: nil)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to be_present
    end

    it "allows the same name under different tenant_ids" do
      described_class.create!(name: "Viewer", tenant_id: 1)
      other = described_class.new(name: "Viewer", tenant_id: 2)

      expect(other).to be_valid
    end
  end
end
