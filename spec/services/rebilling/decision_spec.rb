# typed: false

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

  it "retains supplied diagnostics, trace, and notification intent" do
    outcome = Rebilling::DecisionOutcome.new(status: :exhausted, reason: :max_attempts_reached)
    diagnostics = { attempts: 5, stopped: true, detail: nil }
    trace = [ { branch: :limit, timestamp: Time.current } ]

    decision = described_class.from_outcome(outcome, diagnostics: diagnostics, trace: trace, notification_intent: :notify)

    expect(decision.diagnostics).to equal(diagnostics)
    expect(decision.trace).to equal(trace)
    expect(decision.notification_intent).to eq(:notify)
    expect(decision).to be_exhausted
    expect(decision).not_to be_scheduled
  end

  it "recognizes scheduled decisions without marking them exhausted" do
    outcome = Rebilling::DecisionOutcome.new(status: :scheduled, reason: :initial_attempt_failed)

    decision = described_class.from_outcome(outcome)

    expect(decision).to be_scheduled
    expect(decision).not_to be_exhausted
  end
end
