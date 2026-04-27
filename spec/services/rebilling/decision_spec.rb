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

  it "copies and freezes diagnostics and trace metadata" do
    outcome = Rebilling::DecisionOutcome.new(status: :scheduled, reason: :initial_attempt_failed)
    diagnostics = { gateway: { code: "insufficient_funds" } }
    trace = [ { branch: :candidate_steps } ]

    decision = described_class.from_outcome(outcome, diagnostics: diagnostics, trace: trace)
    diagnostics.fetch(:gateway)[:code] = "mutated"
    trace.first[:branch] = :mutated

    expect(decision.diagnostics).to eq(gateway: { code: "insufficient_funds" })
    expect(decision.trace).to eq([ { branch: :candidate_steps } ])
    expect(decision.diagnostics).to be_frozen
    expect(decision.diagnostics.fetch(:gateway)).to be_frozen
    expect(decision.trace).to be_frozen
    expect(decision.trace.first).to be_frozen
  end
end
