# frozen_string_literal: true

require "rake"

RSpec.describe AccessGrant::Recovery do
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

  describe ".grant_role!" do
    it "grants Owner in multi-tenant mode via owner path" do
      configure_multi!(owner_role: :protected)
      create_permission!("invoices.index")
      org = Organization.create!
      user = User.create!

      described_class.grant_role!(role_name: "Owner", user_id: user.id, tenant_id: org.id)

      owner = org.roles.find { |r| r.name.casecmp("Owner").zero? }
      expect(owner).to be_present
      expect(user.roles.reload).to include(owner)
      expect(user.permitted?("invoices.index", tenant: org)).to be(true)
    end

    it "grants Owner in single-tenant mode" do
      configure_single!(owner_role: :protected)
      create_permission!("invoices.index")
      user = User.create!

      described_class.grant_role!(role_name: "owner", user_id: user.id)

      owner = AccessGrant::Role.find_by("LOWER(name) = ?", "owner")
      expect(owner.tenant_id).to be_nil
      expect(user.roles.reload).to include(owner)
    end

    it "assigns an existing named role" do
      configure_multi!
      org = Organization.create!
      user = User.create!
      viewer = AccessGrant::Role.create!(name: "Viewer", tenant_id: org.id)

      described_class.grant_role!(role_name: "Viewer", user_id: user.id, tenant_id: org.id)

      expect(user.roles.reload).to include(viewer)
    end

    it "is idempotent when role is already assigned" do
      configure_multi!
      org = Organization.create!
      user = User.create!
      viewer = AccessGrant::Role.create!(name: "Viewer", tenant_id: org.id)
      user.roles << viewer

      expect do
        described_class.grant_role!(role_name: "Viewer", user_id: user.id, tenant_id: org.id)
      end.not_to(change { user.roles.count })
    end

    it "raises when role is missing" do
      configure_multi!
      org = Organization.create!
      user = User.create!

      expect do
        described_class.grant_role!(role_name: "Missing", user_id: user.id, tenant_id: org.id)
      end.to raise_error(AccessGrant::Error, /Role not found/)
    end

    it "requires tenant_id for Owner in multi-tenant mode" do
      configure_multi!
      user = User.create!

      expect do
        described_class.grant_role!(role_name: "Owner", user_id: user.id)
      end.to raise_error(AccessGrant::Error, /tenant_id is required/)
    end

    it "requires tenant_id for non-Owner roles in multi-tenant mode" do
      configure_multi!
      org = Organization.create!
      user = User.create!
      AccessGrant::Role.create!(name: "Viewer", tenant_id: org.id)
      AccessGrant::Role.create!(name: "GlobalAdmin", tenant_id: nil)

      expect do
        described_class.grant_role!(role_name: "Viewer", user_id: user.id)
      end.to raise_error(AccessGrant::Error, /tenant_id is required/)

      expect do
        described_class.grant_role!(role_name: "GlobalAdmin", user_id: user.id)
      end.to raise_error(AccessGrant::Error, /tenant_id is required/)
    end

    it "rejects tenant_id in single-tenant mode" do
      configure_single!
      user = User.create!

      expect do
        described_class.grant_role!(role_name: "Owner", user_id: user.id, tenant_id: 1)
      end.to raise_error(AccessGrant::Error, /tenant_id must not be supplied/)
    end

    it "treats owner name as ordinary role when owner_role is :none" do
      configure_multi!(owner_role: :none)
      org = Organization.create!
      user = User.create!
      owner = AccessGrant::Role.create!(name: "Owner", tenant_id: org.id)

      described_class.grant_role!(role_name: "Owner", user_id: user.id, tenant_id: org.id)

      expect(user.roles.reload).to include(owner)
    end
  end

  describe "access_grant:grant_role rake task" do
    before do
      Rake.application = Rake::Application.new
      load File.expand_path("../../lib/tasks/access_grant_tasks.rake", __dir__)
      Rake::Task.define_task(:environment)
    end

    after do
      Rake.application.clear
    end

    it "invokes recover_access when configured" do
      configure_multi!
      org = Organization.create!
      user = User.create!
      seen = nil

      AccessGrant.configure do |config|
        config.recover_access = lambda { |role_name:, user_id:, tenant_id: nil|
          seen = { role_name: role_name, user_id: user_id, tenant_id: tenant_id }
        }
      end

      with_env("ROLE" => "Viewer", "USER_ID" => user.id.to_s, "TENANT_ID" => org.id.to_s) do
        Rake::Task["access_grant:grant_role"].invoke
      end

      expect(seen).to eq(role_name: "Viewer", user_id: user.id, tenant_id: org.id)
    end

    it "falls back to Recovery.grant_role! when recover_access is nil" do
      configure_multi!(owner_role: :protected)
      create_permission!("invoices.index")
      org = Organization.create!
      user = User.create!

      with_env("ROLE" => "Owner", "USER_ID" => user.id.to_s, "TENANT_ID" => org.id.to_s) do
        Rake::Task["access_grant:grant_role"].invoke
      end

      owner = org.roles.find { |r| r.name.casecmp("Owner").zero? }
      expect(user.roles.reload).to include(owner)
    end
  end

  def with_env(vars)
    previous = vars.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end
