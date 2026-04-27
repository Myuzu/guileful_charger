# rubocop:disable RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe Rebilling::DecisionOutcome do
  it "coerces valid status and reason values" do
    outcome = described_class.new(status: "not_retryable", reason: "non_retryable_failure_reason")

    expect(outcome.status).to eq(:not_retryable)
    expect(outcome.reason).to eq(:non_retryable_failure_reason)
  end

  it "rejects invalid status and reason values" do
    expect { described_class.new(status: :unknown, reason: :non_retryable_failure_reason) }.to raise_error(Dry::Types::CoercionError, /decision status/)
    expect { described_class.new(status: :scheduled, reason: :bogus) }.to raise_error(Dry::Types::CoercionError, /decision reason/)
  end
end
