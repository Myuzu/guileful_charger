# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe Rebilling::Attempt do
  def build_attempt(**attributes)
    described_class.new(id: 42, attempt_number: "2", status: "failed", amount_attempted_cents: "300", **attributes)
  end

  it "coerces numeric and symbol fields while retaining IDs and timestamp values" do
    created = Time.utc(2026, 1, 1)
    failed = Time.zone.parse("2026-01-02 12:00:00 UTC")
    attempt = build_attempt(failure_reason: "insufficient_funds", failure_category: "soft_decline",
      retry_step_key: "retry", payment_method_id: nil, strategy_version: 3, created_at: created, failed_at: failed)

    expect(attempt).to have_attributes(id: 42, attempt_number: 2, status: :failed, amount_attempted_cents: 300,
      failure_reason: :insufficient_funds, failure_category: :soft_decline, retry_step_key: :retry,
      payment_method_id: nil, strategy_version: 3, created_at: created, failed_at: failed)
    expect(attempt).to be_frozen
    expect(attempt).not_to be_initial
  end

  it "exposes omitted optional values as nil and recognizes the initial attempt" do
    attempt = build_attempt(id: nil)

    expect(attempt).to have_attributes(id: nil, failure_reason: nil, failure_category: nil, retry_step_key: nil,
      payment_method_id: nil, strategy_version: nil, created_at: nil, completed_at: nil, failed_at: nil)
    expect(attempt).to be_initial
  end

  it "distinguishes terminal, in-flight, and unknown states" do
    %i[completed failed pending scheduled processing custom].each do |status|
      attempt = build_attempt(status: status)

      expect(attempt.completed?).to eq(status == :completed)
      expect(attempt.failed?).to eq(status == :failed)
      expect(attempt.terminal?).to eq(%i[completed failed].include?(status))
      expect(attempt.in_flight?).to eq(%i[pending scheduled processing].include?(status))
    end
  end

  it "leaves invalid numeric input rejection to dry-types" do
    expect { build_attempt(attempt_number: "not a number") }.to raise_error(Dry::Types::CoercionError)
  end
end
