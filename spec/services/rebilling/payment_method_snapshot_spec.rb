# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe Rebilling::PaymentMethodSnapshot do
  it "preserves defaults, nil optional values, unconstrained IDs, and immutability" do
    snapshot = described_class.new(id: 42)

    expect(snapshot).to have_attributes(id: 42, status: :active, primary: false, kind: :card,
      tokenization_kind: nil, last_successful_at: nil, last_failed_at: nil, failure_category: nil)
    expect(snapshot).to be_frozen
    expect(snapshot).not_to be_hard_declined
  end

  it "coerces symbol options and preserves both supported timestamp classes" do
    successful = Time.utc(2026, 1, 1)
    failed = Time.zone.parse("2026-01-02 12:00:00 UTC")
    snapshot = described_class.new(id: nil, status: "active", kind: "card", tokenization_kind: "network_token",
      primary: true, failure_category: "soft_decline", last_successful_at: successful, last_failed_at: failed)

    expect(snapshot).to have_attributes(id: nil, status: :active, kind: :card, tokenization_kind: :network_token,
      primary: true, failure_category: :soft_decline, last_successful_at: successful, last_failed_at: failed)
    expect(snapshot).to be_active
    expect(snapshot).not_to be_hard_declined
  end

  it "allows explicit nil kind and tokenization values" do
    expect(described_class.new(id: "pm_1", kind: nil, tokenization_kind: nil)).to have_attributes(kind: nil, tokenization_kind: nil)
  end

  it "is active only when status is active" do
    expect(described_class.new(id: "pm_1", status: :active)).to be_active
    expect(described_class.new(id: "pm_1", status: :expired)).not_to be_active
  end

  it "is hard declined when the failure category is hard decline" do
    expect(described_class.new(id: "pm_1", failure_category: :hard_decline)).to be_hard_declined
  end

  it "is hard declined when status is ineligible" do
    %i[expired invalid requires_action disabled].each do |status|
      expect(described_class.new(id: "pm_1", status: status)).to be_hard_declined
    end
  end

  it "rejects non-boolean primary values through dry-types" do
    expect { described_class.new(id: "pm_1", primary: "true") }.to raise_error(Dry::Types::ConstraintError)
  end
end
