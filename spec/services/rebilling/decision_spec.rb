# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe Rebilling::Decision do
  it "builds from an outcome with safe defaults" do
    outcome = Rebilling::DecisionOutcome.new(status: :scheduled, reason: :initial_attempt_failed)

    decision = described_class.from_outcome(outcome)

    expect(decision.status).to eq(:scheduled)
    expect(decision.reason).to eq(:initial_attempt_failed)
    expect(decision.plan).to be_nil
    expect(decision.diagnostics).to eq({})
    expect(decision.trace).to eq([])
    expect(decision.notification_intent).to eq(:none)
  end

  it "reports scheduled and exhausted outcomes" do
    scheduled = described_class.from_outcome(Rebilling::DecisionOutcome.new(status: :scheduled, reason: :initial_attempt_failed))
    exhausted = described_class.from_outcome(Rebilling::DecisionOutcome.new(status: :exhausted, reason: :max_attempts_reached))

    aggregate_failures do
      expect(scheduled.scheduled?).to be(true)
      expect(scheduled.exhausted?).to be(false)
      expect(exhausted.scheduled?).to be(false)
      expect(exhausted.exhausted?).to be(true)
    end
  end
end
