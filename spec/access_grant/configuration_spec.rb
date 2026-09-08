# frozen_string_literal: true

RSpec.describe AccessGrant::Configuration do
  before { AccessGrant.reset_config! }

  it "defaults owner_role to :protected and user_class to User" do
    config = described_class.new
    expect(config.owner_role).to eq(:protected)
    expect(config.owner_role_name).to eq("Owner")
    expect(config.user_class).to eq("User")
    expect(config.tenant_class).to be_nil
    expect(config.default_permission_actions).to eq(%w[index show create update destroy])
    expect(config.current_user_method).to eq(:current_user)
    expect(config.current_tenant_method).to eq(:current_tenant)
    expect(config.tables).to include(
      roles: "roles",
      permissions: "permissions",
      role_permissions: "role_permissions",
      user_roles: "user_roles"
    )
  end

  describe "AccessGrant.configure" do
    it "yields and mutates the shared config" do
      AccessGrant.configure do |config|
        config.user_class = "Account"
        config.owner_role = :none
      end

      expect(AccessGrant.config.user_class).to eq("Account")
      expect(AccessGrant.config.owner_role).to eq(:none)
    end
  end

  describe "AccessGrant.reset_config!" do
    it "restores defaults after mutation" do
      AccessGrant.configure { |config| config.user_class = "Account" }
      AccessGrant.reset_config!

      expect(AccessGrant.config.user_class).to eq("User")
    end
  end
end
