# frozen_string_literal: true

RSpec.describe "ActiveRecord test harness" do
  it "connects" do
    expect(ActiveRecord::Base.connection).to be_active
  end
end
