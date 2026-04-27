# rubocop:disable RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe Rebilling::PaymentMethodSnapshot do
  it "is active only when status is active" do
    expect(described_class.new(id: "pm_1", status: :active)).to be_active
    expect(described_class.new(id: "pm_1", status: :expired)).not_to be_active
  end

  it "is hard declined when the failure category is hard decline" do
    expect(described_class.new(id: "pm_1", failure_category: :hard_decline)).to be_hard_declined
  end

  it "is hard declined when status is ineligible" do
    expect(described_class.new(id: "pm_1", status: :invalid)).to be_hard_declined
    expect(described_class.new(id: "pm_1", status: :requires_action)).to be_hard_declined
  end
end
