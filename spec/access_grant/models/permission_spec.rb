# frozen_string_literal: true

RSpec.describe AccessGrant::Permission do
  it "uses the configured permissions table name" do
    expect(described_class.table_name).to eq(AccessGrant.config.tables.fetch(:permissions))
  end

  it "accepts a valid permission key" do
    permission = described_class.new(key: "invoices.index")
    expect(permission).to be_valid
  end

  it "rejects a malformed permission key" do
    permission = described_class.new(key: "manage_billing")
    expect(permission).not_to be_valid
    expect(permission.errors[:key]).to be_present
  end

  it "rejects a duplicate key" do
    described_class.create!(key: "invoices.index")
    duplicate = described_class.new(key: "invoices.index")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:key]).to be_present
  end

  describe ".by_category" do
    it "returns permissions for a model/controller category ordered by key" do
      described_class.create!(key: "invoices.update", category: "invoices")
      described_class.create!(key: "invoices.index", category: "invoices")
      described_class.create!(key: "billing.export", category: "billing")

      keys = described_class.by_category("invoices").pluck(:key)
      expect(keys).to eq(%w[invoices.index invoices.update])
    end
  end

  describe ".ordered_for_ui" do
    it "orders by category then key" do
      described_class.create!(key: "invoices.index", category: "invoices")
      described_class.create!(key: "billing.export", category: "billing")

      expect(described_class.ordered_for_ui.pluck(:key)).to eq(
        %w[billing.export invoices.index]
      )
    end
  end
end
