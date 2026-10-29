# typed: false

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

  it "freezes the normalized outcome" do
    outcome = described_class.new(status: "scheduled", reason: "initial_attempt_failed")

    expect(outcome).to be_frozen
    expect { outcome.instance_variable_set(:@status, :exhausted) }.to raise_error(FrozenError)
    expect(outcome.status).to eq(:scheduled)
  end

  it "preserves dry-initializer errors for missing required options" do
    expect { described_class.new(reason: :initial_attempt_failed) }.to raise_error(KeyError, /status/)
    expect { described_class.new(status: :scheduled) }.to raise_error(KeyError, /reason/)
  end

  it "leaves custom symbol coercion to dry-types" do
    status = instance_double(String, to_sym: :scheduled)
    reason = instance_double(String, to_sym: :initial_attempt_failed)

    outcome = described_class.new(status: status, reason: reason)

    expect(outcome).to have_attributes(status: :scheduled, reason: :initial_attempt_failed)
  end

  it "preserves initialization and freezing for subclasses" do
    specialized = Class.new(described_class)

    outcome = specialized.new(status: "scheduled", reason: "initial_attempt_failed")

    expect(outcome).to be_an_instance_of(specialized)
    expect(outcome).to have_attributes(status: :scheduled, reason: :initial_attempt_failed)
    expect(outcome).to be_frozen
  end
end
