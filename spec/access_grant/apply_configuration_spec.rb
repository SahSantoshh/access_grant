# frozen_string_literal: true

RSpec.describe "AccessGrant.apply_configuration!" do
  after { AccessGrant.reset_config! }

  it "refreshes arel_table when table names change after configure" do
    expect(AccessGrant::Permission.arel_table.name).to eq("permissions")

    AccessGrant.configure do |config|
      config.tables[:permissions] = "access_grant_permissions"
    end

    expect(AccessGrant::Permission.table_name).to eq("access_grant_permissions")
    expect(AccessGrant::Permission.arel_table.name).to eq("access_grant_permissions")
  end

  it "picks up custom table names after configure" do
    AccessGrant.configure do |config|
      config.tables[:permissions] = "access_grant_permissions"
    end

    expect(AccessGrant::Permission.table_name).to eq("access_grant_permissions")
  end

  it "defines Role belongs_to :tenant when tenant_class is set" do
    AccessGrant.configure do |config|
      config.tenant_class = "Organization"
    end

    reflection = AccessGrant::Role.reflect_on_association(:tenant)
    expect(reflection).not_to be_nil
    expect(reflection.options[:class_name]).to eq("Organization")
    expect(reflection.foreign_key.to_s).to eq("tenant_id")
  end

  it "restores default table names and clears tenant association after reset_config!" do
    AccessGrant.configure do |config|
      config.tables[:permissions] = "access_grant_permissions"
      config.tables[:roles] = "access_grant_roles"
      config.tables[:role_permissions] = "access_grant_role_permissions"
      config.tenant_class = "Organization"
    end

    AccessGrant.reset_config!

    expect(AccessGrant::Permission.table_name).to eq("permissions")
    expect(AccessGrant::Role.table_name).to eq("roles")
    expect(AccessGrant::RolePermission.table_name).to eq("role_permissions")
    expect(AccessGrant::Role.reflect_on_association(:tenant)).to be_nil
  end
end
