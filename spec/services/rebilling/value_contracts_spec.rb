# typed: false

# Cross-value compatibility checks span several Data classes.
# rubocop:disable RSpec/DescribeClass, RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe "Rebilling value contracts" do
  it "preserves Data construction, immutability, and partial updates for each typed value" do
    now = Time.current
    plan = Rebilling::Plan.new(step_key: :retry, payment_method_id: 42, attempt_number: 2,
      amount_cents: 300, retry_at: now, earliest_retry_at: now, latest_retry_at: now,
      retry_strategy: :invoice_total, idempotency_key: "retry:2", strategy_version: 1, source_attempt_id: nil)
    values = [
      plan,
      Rebilling::FailureClassification.new(category: :soft_decline, network_recommendation: nil,
        retryable: true, requires_credential_refresh: false, customer_action_required: false),
      Rebilling::Decision.from_outcome(Rebilling::DecisionOutcome.new(status: :scheduled, reason: :initial_attempt_failed), plan: plan),
      Rebilling::RetryStep::AmountCalculation.new(base_cents: 1200, calculated_amount_cents: 300, capped_amount_cents: 300)
    ]

    values.each do |value|
      expect(value).to be_frozen
      expect(value.class.new(*value.to_h.values)).to eq(value)
      expect(value.class[**value.to_h]).to eq(value)
      expect(value.with).to equal(value)

      specialized = Class.new(value.class)
      derived = specialized.new(**value.to_h)
      expect(derived).to be_an_instance_of(specialized)
      expect(specialized[*value.to_h.values]).to eq(derived)
      expect(derived.with(**value.to_h)).to be_an_instance_of(specialized)
      expect(derived.deconstruct_keys(nil)).to eq(value.to_h)
      expect(derived).to be_frozen
    end
    expect(plan.with(amount_cents: 100).amount_cents).to eq(100)
    expect(plan.amount_cents).to eq(300)
    expect(plan.payment_method_id).to eq(42)
    expect(plan.source_attempt_id).to be_nil
  end

  it "preserves inherited dry constructors and their frozen normalized state" do
    inputs = {
      Rebilling::Attempt => { id: nil, attempt_number: "2", status: "failed", amount_attempted_cents: "300" },
      Rebilling::Context => { invoice_id: 42, invoice_status: "open", invoice_total_cents: "1200",
        amount_paid_cents: "0", subscription_status: "active" },
      Rebilling::PaymentMethodSnapshot => { id: nil, status: "active" },
      Rebilling::RetryStep => { percentage: "12.5", delay: "60", key: "custom" }
    }

    inputs.each do |base, options|
      specialized = Class.new(base)
      value = specialized.new(**options)

      expect(value).to be_an_instance_of(specialized)
      expect(value).to be_frozen
    end
  end
end
