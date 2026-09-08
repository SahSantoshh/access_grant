# frozen_string_literal: true

RSpec.describe AccessGrant::Catalog do
  before do
    AccessGrant.reset_config!
    AccessGrant.reset_catalog!
  end

  describe "AccessGrant.permissions" do
    it "emits default actions with templated descriptions for a resource" do
      AccessGrant.permissions do
        resource :invoices
      end

      entries = AccessGrant.catalog.entries
      expect(entries.map { |e| e[:key] }).to include("invoices.index", "invoices.destroy")
      expect(entries.find { |e| e[:key] == "invoices.index" }[:description]).to match(/list/i)
      expect(entries.find { |e| e[:key] == "invoices.index" }[:category]).to eq("invoices")
    end

    it "pluralizes singular resource names for key segments" do
      AccessGrant.permissions do
        resource :invoice
      end

      keys = AccessGrant.catalog.entries.map { |e| e[:key] }
      expect(keys).to include("invoices.index")
    end

    it "accepts plural resource names unchanged" do
      AccessGrant.permissions do
        resource :invoices
      end

      keys = AccessGrant.catalog.entries.map { |e| e[:key] }
      expect(keys).to include("invoices.show")
    end

    it "interpolates resource and resources in default templates" do
      AccessGrant.permissions do
        resource :invoices
      end

      entries = AccessGrant.catalog.entries
      expect(entries.find { |e| e[:key] == "invoices.show" }[:description]).to eq("Can view details of a invoice")
      expect(entries.find { |e| e[:key] == "invoices.index" }[:description]).to eq("Can view list of invoices")
    end

    it "adds custom actions inside a resource block" do
      AccessGrant.permissions do
        resource :invoices do
          action :couple, description: "Can couple invoices together"
        end
      end

      entry = AccessGrant.catalog.entries.find { |e| e[:key] == "invoices.couple" }
      expect(entry[:description]).to eq("Can couple invoices together")
      expect(entry[:category]).to eq("invoices")
    end

    it "allows overriding a default action description" do
      AccessGrant.permissions do
        resource :invoices do
          action :index, description: "List all invoices"
        end
      end

      entry = AccessGrant.catalog.entries.find { |e| e[:key] == "invoices.index" }
      expect(entry[:description]).to eq("List all invoices")
    end

    it "sets category from a category block for nested declarations" do
      AccessGrant.permissions do
        category "billing" do
          permission "billing.export", "Export billing CSV"
        end
      end

      entry = AccessGrant.catalog.entries.find { |e| e[:key] == "billing.export" }
      expect(entry[:description]).to eq("Export billing CSV")
      expect(entry[:category]).to eq("billing")
    end

    it "replaces the catalog on each permissions block" do
      AccessGrant.permissions { resource :invoices }
      AccessGrant.permissions { resource :providers }

      keys = AccessGrant.catalog.entries.map { |e| e[:key] }
      expect(keys).to include("providers.index")
      expect(keys).not_to include("invoices.index")
    end

    it "raises for invalid permission keys" do
      expect do
        AccessGrant.permissions do
          category "billing" do
            permission "manage_billing", "Bad key"
          end
        end
      end.to raise_error(AccessGrant::Error, /Invalid permission key/)
    end

    it "raises for duplicate key declarations" do
      expect do
        AccessGrant.permissions do
          resource :invoices do
            action :couple, description: "First"
            action :couple, description: "Second"
          end
        end
      end.to raise_error(AccessGrant::Error, /Duplicate permission key/)
    end

    it "raises when a custom default action lacks a template and description" do
      AccessGrant.configure { |c| c.default_permission_actions = %w[index search] }

      expect do
        AccessGrant.permissions { resource :invoices }
      end.to raise_error(AccessGrant::Error, /requires an explicit description/)
    end

    it "allows custom default actions when explicitly described in the block" do
      AccessGrant.configure { |c| c.default_permission_actions = %w[index search] }

      AccessGrant.permissions do
        resource :invoices do
          action :search, description: "Can search invoices"
        end
      end

      entry = AccessGrant.catalog.entries.find { |e| e[:key] == "invoices.search" }
      expect(entry[:description]).to eq("Can search invoices")
    end

    it "raises when an empty resource block omits an untemplated default" do
      AccessGrant.configure { |c| c.default_permission_actions = %w[index search] }

      expect do
        AccessGrant.permissions do
          resource :invoices do
          end
        end
      end.to raise_error(AccessGrant::Error, /Default action :search requires an explicit description/)
    end

    it "raises for cross-declaration duplicate via action key override" do
      expect do
        AccessGrant.permissions do
          resource :invoices
          resource :providers do
            action :takeover, key: "invoices.index", description: "Steal invoices index"
          end
        end
      end.to raise_error(AccessGrant::Error, /Duplicate permission key: invoices\.index/)
    end

    it "raises when a second resource re-declares the same default keys" do
      expect do
        AccessGrant.permissions do
          resource :invoices
          resource :invoices
        end
      end.to raise_error(AccessGrant::Error, /Duplicate permission key: invoices\.index/)
    end
  end
end
