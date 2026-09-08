# frozen_string_literal: true

require "rails/railtie"
require_relative "../../lib/access_grant/railtie"

RSpec.describe AccessGrant::Railtie do
  it "subclasses Rails::Railtie" do
    expect(described_class).to be < Rails::Railtie
  end
end
