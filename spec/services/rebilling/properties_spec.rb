# rubocop:disable RSpec/DescribeClass, RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe "Rebilling strategy properties" do
  include RebillingHelpers

  def context_for(invoice_id:, source_attempt_id:, payment_method_id:, amount_paid_cents:, step_key: nil)
    retry_step_key = step_key || :charge_25pct_invoice_total_after_60s
    attempt = build_attempt(id:                source_attempt_id,
                            attempt_number:    2,
                            failure_category:  :soft_decline,
                            retry_step_key:    retry_step_key,
                            payment_method_id: payment_method_id)
    build_context(invoice_id:        invoice_id,
                  amount_paid_cents: amount_paid_cents,
                  attempts:          [ attempt ],
                  payment_methods:   [ build_payment_method(payment_method_id) ])
  end

  let(:now) { Time.zone.parse("2026-01-01 12:00:00 UTC") }
  let(:strategy) do
    Rebilling::DunningStrategy.build(version: 5) do
      step 25, delay: 1.minute, jitter: 0..120.seconds
      step 15, delay: 5.minutes
    end
  end

  it "keeps scheduled amounts capped, monotonic, deterministic, and inside the retry window" do
    contexts = [
      context_for(invoice_id: "inv_1", source_attempt_id: "pa_1", payment_method_id: "pm_1", amount_paid_cents: 1_000),
      context_for(invoice_id: "inv_2", source_attempt_id: "pa_2", payment_method_id: "pm_2", amount_paid_cents: 0),
      context_for(invoice_id: "inv_3", source_attempt_id: "pa_3", payment_method_id: "pm_3", amount_paid_cents: 600)
    ]

    contexts.each do |context|
      first_decision = strategy.next_plan(context, now: now)
      second_decision = strategy.next_plan(context, now: now)

      aggregate_failures do
        expect(first_decision.plan.amount_cents).to be <= context.amount_remaining_cents
        expect(first_decision.plan.attempt_number).to eq(context.latest_terminal_attempt.attempt_number + 1)
        expect(first_decision.plan.retry_at).to be_between(first_decision.plan.earliest_retry_at, first_decision.plan.latest_retry_at).inclusive
        expect(second_decision).to eq(first_decision)
      end
    end
  end

  it "produces distinct idempotency keys for distinct source tuples" do
    first = strategy.next_plan(context_for(invoice_id: "inv_1", source_attempt_id: "pa_1", payment_method_id: "pm_1", amount_paid_cents: 0), now: now)
    second = strategy.next_plan(context_for(invoice_id: "inv_2", source_attempt_id: "pa_1", payment_method_id: "pm_1", amount_paid_cents: 0), now: now)
    third = strategy.next_plan(context_for(invoice_id: "inv_1", source_attempt_id: "pa_2", payment_method_id: "pm_1", amount_paid_cents: 0), now: now)

    expect([ first.plan.idempotency_key, second.plan.idempotency_key, third.plan.idempotency_key ].uniq.size).to eq(3)
  end
end
