# frozen_string_literal: true

RSpec.describe AccessGrant::PermissionKey do
  describe ".valid?" do
    it "returns true for a well-formed key" do
      expect(described_class.valid?("invoices.index")).to be true
    end

    it "accepts symbols after to_s conversion" do
      expect(described_class.valid?(:"invoices.index")).to be true
    end

    it "returns false when the dot is missing" do
      expect(described_class.valid?("manage_billing")).to be false
    end

    it "returns false for uppercase letters" do
      expect(described_class.valid?("Invoices.Index")).to be false
    end

    it "returns false when a segment starts with a digit" do
      expect(described_class.valid?("1invoices.index")).to be false
      expect(described_class.valid?("invoices.1index")).to be false
    end

    it "returns false for empty segments" do
      expect(described_class.valid?(".index")).to be false
      expect(described_class.valid?("invoices.")).to be false
    end
  end

  describe ".normalize!" do
    it "returns the string for a valid key" do
      expect(described_class.normalize!("invoices.index")).to eq("invoices.index")
    end

    it "accepts a symbol whose to_s matches the format" do
      expect(described_class.normalize!(:"invoices.index")).to eq("invoices.index")
    end

    it "raises for a symbol without a dot" do
      expect { described_class.normalize!(:invoices_update) }
        .to raise_error(AccessGrant::Error)
    end

    it "raises for uppercase letters" do
      expect { described_class.normalize!("Invoices.Index") }
        .to raise_error(AccessGrant::Error)
    end

    it "raises when the dot is missing" do
      expect { described_class.normalize!("manage_billing") }
        .to raise_error(AccessGrant::Error)
    end
  end
end
