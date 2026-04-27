# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers
require "rails_helper"

RSpec.describe Rebilling::DunningStrategy do
  include RebillingHelpers

  let(:now) { Time.zone.parse("2026-01-01 12:00:00 UTC") }
  let(:step_75pct)         { Rebilling::RetryStep.new(percentage: 75, delay: 1.day) }
  let(:step_50pct)         { Rebilling::RetryStep.new(percentage: 50, delay: 1.day) }
  let(:step_25pct_slow)    { Rebilling::RetryStep.new(percentage: 25, delay: 5.minutes, on_success: :next) }
  let(:step_25pct_fast)    { Rebilling::RetryStep.new(percentage: 25, delay: 1.minute) }
  let(:step_15pct)         { Rebilling::RetryStep.new(percentage: 15, delay: 5.minutes) }
  let(:remaining_balance_step) { Rebilling::RetryStep.new(percentage: 50, basis: :remaining_balance, delay: 2.minutes) }
  let(:strategy) do
    described_class.new(version:      3,
                        steps:        [ step_75pct, step_50pct, step_25pct_slow, step_25pct_fast, step_15pct ],
                        max_attempts: 8)
  end

  describe "DSL and validation" do
    it "builds strategies with the compact step DSL" do
      dsl_strategy = described_class.build(version: 7, max_attempts: 4) do
        step 25, delay: 5.minutes, on_success: :next
        step 25, delay: 1.minute
      end

      expect(dsl_strategy.version).to eq(7)
      expect(dsl_strategy.max_attempts).to eq(4)
      expect(dsl_strategy.steps.map(&:key)).to eq(%i[charge_25pct_invoice_total_after_300s charge_25pct_invoice_total_after_60s])
    end

    it "rejects duplicate retry step keys" do
      duplicate_step = Rebilling::RetryStep.new(percentage: 75, delay: 1.day)

      expect {
        described_class.new(steps: [ step_75pct, duplicate_step ])
      }.to raise_error(ArgumentError, /duplicate retry step key/)
    end

    it "rejects non-retry-step strategy steps" do
      expect {
        described_class.new(steps: [ "not-a-step" ])
      }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe "#next_plan guards" do
    it "returns invoice-paid when the invoice is already fully paid" do
      failed_attempt = build_attempt(attempt_number: 2, retry_step_key: step_75pct.key, failure_category: :soft_decline)

      decision = strategy.next_plan(build_context(attempts: [ failed_attempt ], amount_paid_cents: 1200, payment_methods: [ build_payment_method ]), now: now)

      expect(decision.status).to eq(:invoice_paid)
      expect(decision.reason).to eq(:invoice_already_paid)
    end

    it "returns not-retryable when the invoice is no longer retryable" do
      failed_attempt = build_attempt(attempt_number: 2, retry_step_key: step_75pct.key, failure_category: :soft_decline)

      decision = strategy.next_plan(build_context(invoice_status: :not_paid, attempts: [ failed_attempt ], payment_methods: [ build_payment_method ]), now: now)

      expect(decision.status).to eq(:not_retryable)
      expect(decision.reason).to eq(:invoice_not_retryable)
    end

    it "returns subscription-inactive when the subscription paused or cancelled mid-cycle" do
      failed_attempt = build_attempt(attempt_number: 2, retry_step_key: step_75pct.key, failure_category: :soft_decline)

      paused_decision = strategy.next_plan(build_context(attempts: [ failed_attempt ], subscription_status: :paused, payment_methods: [ build_payment_method ]), now: now)
      cancelled_decision = strategy.next_plan(build_context(attempts: [ failed_attempt ], subscription_status: :cancelled, payment_methods: [ build_payment_method ]), now: now)

      aggregate_failures do
        expect(paused_decision.status).to eq(:subscription_inactive)
        expect(paused_decision.reason).to eq(:subscription_not_active)
        expect(cancelled_decision.status).to eq(:subscription_inactive)
      end
    end

    it "returns in-flight when an attempt is already pending, scheduled, or processing" do
      scheduled = build_attempt(attempt_number: 2, status: :scheduled, retry_step_key: step_75pct.key)

      decision = strategy.next_plan(build_context(attempts: [ scheduled ], payment_methods: [ build_payment_method ]), now: now)

      expect(decision.status).to eq(:in_flight_attempt_exists)
    end

    it "returns not-retryable when there is no terminal attempt" do
      decision = strategy.next_plan(build_context(attempts: [], payment_methods: [ build_payment_method ]), now: now)

      expect(decision.status).to eq(:not_retryable)
      expect(decision.reason).to eq(:no_terminal_attempt)
    end

    it "schedules at max attempts minus one and exhausts at max attempts" do
      almost_exhausted = build_attempt(attempt_number: 7, retry_step_key: step_25pct_fast.key, failure_category: :soft_decline)
      exhausted = build_attempt(attempt_number: 8, retry_step_key: step_25pct_fast.key, failure_category: :soft_decline)
      methods = [ build_payment_method ]

      scheduled_decision = strategy.next_plan(build_context(attempts: [ almost_exhausted ], payment_methods: methods), now: now)
      exhausted_decision = strategy.next_plan(build_context(attempts: [ exhausted ], payment_methods: methods), now: now)

      aggregate_failures do
        expect(scheduled_decision).to be_scheduled
        expect(scheduled_decision.plan.attempt_number).to eq(8)
        expect(exhausted_decision).to be_exhausted
        expect(exhausted_decision.reason).to eq(:max_attempts_reached)
      end
    end

    it "returns a clear reason when the previous retry step key is unknown" do
      unknown_step_attempt = build_attempt(attempt_number: 2, retry_step_key: :charge_99pct_unknown_after_1s, failure_category: :soft_decline)

      decision = strategy.next_plan(build_context(attempts: [ unknown_step_attempt ], payment_methods: [ build_payment_method ]), now: now)

      expect(decision.status).to eq(:not_retryable)
      expect(decision.reason).to eq(:unknown_step_key)
    end
  end

  describe "#next_plan step selection" do
    it "schedules the first retry step after an initial retryable failure" do
      initial_attempt = build_attempt(id: "pa_initial", attempt_number: 1, retry_step_key: nil, failure_category: :soft_decline)

      context = build_context(attempts: [ initial_attempt ], payment_methods: [ build_payment_method ])
      decision = strategy.next_plan(context, now: now)

      aggregate_failures do
        expect(decision).to be_scheduled
        expect(decision.reason).to eq(:initial_attempt_failed)
        expect(decision.plan.step_key).to eq(step_75pct.key)
        expect(decision.plan.amount_cents).to eq(900)
        expect(decision.plan.attempt_number).to eq(2)
        expect(decision.plan.strategy_version).to eq(3)
        expect(decision.plan.idempotency_key).to start_with("rebill:#{context.invoice_id}:pa_initial:v3:#{step_75pct.key}:")
        expect(decision.plan.idempotency_key).to end_with(":pm_primary")
      end
    end

    it "falls through ordered steps after retryable failures" do
      failed_75 = build_attempt(attempt_number: 2, retry_step_key: step_75pct.key, failure_category: :soft_decline)

      decision = strategy.next_plan(build_context(attempts: [ failed_75 ], payment_methods: [ build_payment_method ]), now: now)

      expect(decision.plan.step_key).to eq(step_50pct.key)
      expect(decision.plan.amount_cents).to eq(600)
    end

    it "uses the selected step basis for amount calculation and retry strategy" do
      basis_strategy = described_class.new(steps: [ step_75pct, remaining_balance_step ])
      failed_75 = build_attempt(attempt_number: 2, retry_step_key: step_75pct.key, failure_category: :soft_decline)

      decision = basis_strategy.next_plan(build_context(attempts: [ failed_75 ], amount_paid_cents: 900, payment_methods: [ build_payment_method ]), now: now)

      aggregate_failures do
        expect(decision.plan.step_key).to eq(remaining_balance_step.key)
        expect(decision.plan.amount_cents).to eq(150)
        expect(decision.plan.retry_strategy).to eq(:remaining_balance)
      end
    end

    it "transitions to a faster same-percentage step after configured success" do
      completed_25 = build_attempt(attempt_number: 4, status: :completed, retry_step_key: step_25pct_slow.key)

      decision = strategy.next_plan(build_context(attempts: [ completed_25 ], amount_paid_cents: 300, payment_methods: [ build_payment_method ]), now: now)

      aggregate_failures do
        expect(decision.reason).to eq(:last_step_succeeded)
        expect(decision.plan.step_key).to eq(step_25pct_fast.key)
        expect(decision.plan.amount_cents).to eq(300)
        expect(decision.plan.earliest_retry_at).to eq(now + 1.minute)
      end
    end

    it "repeats a successful step by default" do
      completed_25 = build_attempt(attempt_number: 5, status: :completed, retry_step_key: step_25pct_fast.key)

      decision = strategy.next_plan(build_context(attempts: [ completed_25 ], amount_paid_cents: 600, payment_methods: [ build_payment_method ]), now: now)

      expect(decision.plan.step_key).to eq(step_25pct_fast.key)
      expect(decision.plan.amount_cents).to eq(300)
    end

    it "caps amount by remaining balance" do
      completed_75 = build_attempt(attempt_number: 2, status: :completed, retry_step_key: step_75pct.key)

      decision = strategy.next_plan(build_context(attempts: [ completed_75 ], amount_paid_cents: 1_000, payment_methods: [ build_payment_method ]), now: now)

      expect(decision.plan.step_key).to eq(step_75pct.key)
      expect(decision.plan.amount_cents).to eq(200)
    end

    it "returns non-retryable when an initial failure has no configured steps" do
      empty_strategy = described_class.new(steps: [])
      initial_attempt = build_attempt(attempt_number: 1, retry_step_key: nil, failure_category: :soft_decline)

      decision = empty_strategy.next_plan(build_context(attempts: [ initial_attempt ], payment_methods: [ build_payment_method ]), now: now)

      expect(decision.status).to eq(:not_retryable)
      expect(decision.reason).to eq(:non_retryable_failure_reason)
    end
  end

  describe "#next_plan payment method waterfall" do
    it "tries another payment method for the same failed step before falling back" do
      failed_25 = build_attempt(attempt_number: 6, retry_step_key: step_25pct_fast.key, failure_category: :soft_decline)
      primary = build_payment_method("pm_primary", primary: true)
      backup = build_payment_method("pm_backup")

      decision = strategy.next_plan(build_context(attempts: [ failed_25 ], amount_paid_cents: 600, payment_methods: [ primary, backup ]), now: now)

      expect(decision.plan.step_key).to eq(step_25pct_fast.key)
      expect(decision.plan.payment_method_id).to eq("pm_backup")
    end

    it "falls back to the next lower step after all methods failed for the current step" do
      failed_primary = build_attempt(id: "pa_primary", attempt_number: 6, retry_step_key: step_25pct_fast.key, payment_method_id: "pm_primary", failure_category: :soft_decline)
      failed_backup = build_attempt(id: "pa_backup", attempt_number: 7, retry_step_key: step_25pct_fast.key, payment_method_id: "pm_backup", failure_category: :soft_decline)
      primary = build_payment_method("pm_primary", primary: true)
      backup = build_payment_method("pm_backup")

      decision = strategy.next_plan(build_context(attempts: [ failed_primary, failed_backup ], amount_paid_cents: 600, payment_methods: [ primary, backup ]), now: now)

      aggregate_failures do
        expect(decision.plan.step_key).to eq(step_15pct.key)
        expect(decision.plan.payment_method_id).to eq("pm_primary")
        expect(decision.plan.amount_cents).to eq(180)
      end
    end

    it "does not waterfall through payment methods when configured not to exhaust methods per step" do
      no_waterfall_strategy = described_class.new(steps:                 [ step_75pct, step_50pct ],
                                                  payment_method_policy: Rebilling::PaymentMethodPolicy.new(exhaust_methods_per_step: false))
      failed_75 = build_attempt(attempt_number: 2, retry_step_key: step_75pct.key, failure_category: :soft_decline)
      primary = build_payment_method("pm_primary", primary: true)
      backup = build_payment_method("pm_backup")

      decision = no_waterfall_strategy.next_plan(build_context(attempts: [ failed_75 ], payment_methods: [ primary, backup ]), now: now)

      expect(decision.plan.step_key).to eq(step_50pct.key)
      expect(decision.plan.payment_method_id).to eq("pm_primary")
    end

    it "returns no eligible payment method when no method can be selected" do
      initial_attempt = build_attempt(attempt_number: 1, retry_step_key: nil, failure_category: :soft_decline)
      inactive_method = build_payment_method("pm_expired", status: :expired)

      empty_methods_decision = strategy.next_plan(build_context(attempts: [ initial_attempt ], payment_methods: []), now: now)
      inactive_methods_decision = strategy.next_plan(build_context(attempts: [ initial_attempt ], payment_methods: [ inactive_method ]), now: now)

      aggregate_failures do
        expect(empty_methods_decision.status).to eq(:no_eligible_payment_method)
        expect(empty_methods_decision.reason).to eq(:no_eligible_payment_method)
        expect(inactive_methods_decision.status).to eq(:no_eligible_payment_method)
      end
    end
  end

  describe "#next_plan exhaustion paths" do
    it "returns exhausted when a step stops the chain after success" do
      stop_after_success = Rebilling::RetryStep.new(percentage: 25, delay: 1.minute, on_success: :stop)
      stop_strategy = described_class.new(steps: [ stop_after_success ])
      completed_attempt = build_attempt(attempt_number: 2, status: :completed, retry_step_key: stop_after_success.key)

      decision = stop_strategy.next_plan(build_context(attempts: [ completed_attempt ], amount_paid_cents: 300, payment_methods: [ build_payment_method ]), now: now)

      expect(decision).to be_exhausted
      expect(decision.reason).to eq(:step_chain_stopped)
    end

    it "returns exhausted when the final step stops after failure and methods are exhausted" do
      stop_strategy = described_class.default
      final_step = stop_strategy.steps.last
      failed_final = build_attempt(attempt_number: 11, retry_step_key: final_step.key, failure_category: :soft_decline)
      primary = build_payment_method("pm_primary", primary: true)

      decision = stop_strategy.next_plan(build_context(attempts: [ failed_final ], payment_methods: [ primary ]), now: now)

      expect(decision).to be_exhausted
      expect(decision.reason).to eq(:step_chain_stopped)
    end

    it "returns exhausted when the final step has no successor" do
      final_failed = build_attempt(attempt_number: 2, retry_step_key: step_15pct.key, failure_category: :soft_decline)
      primary = build_payment_method("pm_primary", primary: true)

      decision = strategy.next_plan(build_context(attempts: [ final_failed ], payment_methods: [ primary ]), now: now)

      expect(decision).to be_exhausted
      expect(decision.reason).to eq(:no_next_step)
    end
  end

  describe "#next_plan non-retryable paths" do
    it "returns not retryable for non-retryable failure categories" do
      hard_decline = build_attempt(attempt_number: 1, failure_category: :hard_decline)

      decision = strategy.next_plan(build_context(attempts: [ hard_decline ], payment_methods: [ build_payment_method ]), now: now)

      expect(decision.status).to eq(:not_retryable)
      expect(decision.reason).to eq(:non_retryable_failure_reason)
    end

    it "returns customer action failures as non-retryable" do
      customer_action = build_attempt(attempt_number: 1, failure_reason: :authentication_required)

      decision = strategy.next_plan(build_context(attempts: [ customer_action ], payment_methods: [ build_payment_method ]), now: now)

      expect(decision.status).to eq(:not_retryable)
      expect(decision.reason).to eq(:non_retryable_failure_reason)
    end

    it "returns technical and unknown failures as non-retryable for business dunning" do
      technical_failure = build_attempt(id: "pa_tech", attempt_number: 1, failure_reason: :system_error)
      unknown_failure = build_attempt(id: "pa_unknown", attempt_number: 2)
      methods = [ build_payment_method ]

      technical_decision = strategy.next_plan(build_context(attempts: [ technical_failure ], payment_methods: methods), now: now)
      unknown_decision = strategy.next_plan(build_context(attempts: [ unknown_failure ], payment_methods: methods), now: now)

      aggregate_failures do
        expect(technical_decision.status).to eq(:not_retryable)
        expect(unknown_decision.status).to eq(:not_retryable)
      end
    end

    it "returns a reconciliation-specific reason when an initial attempt completed before invoice reconciliation" do
      completed_initial = build_attempt(attempt_number: 1, status: :completed, retry_step_key: nil)

      decision = strategy.next_plan(build_context(attempts: [ completed_initial ], payment_methods: [ build_payment_method ]), now: now)

      expect(decision.status).to eq(:not_retryable)
      expect(decision.reason).to eq(:completed_initial_attempt_not_reconciled)
    end
  end

  describe "#next_plan diagnostics" do
    it "exposes scheduled decision diagnostics as a stable observability contract" do
      initial_attempt = build_attempt(id: "pa_diag", attempt_number: 1, retry_step_key: nil, failure_category: :soft_decline)
      context = build_context(attempts: [ initial_attempt ], payment_methods: [ build_payment_method ])

      decision = strategy.next_plan(context, now: now)

      expect(decision.diagnostics).to include(invoice_id:                 context.invoice_id,
                                              invoice_total_cents:        1200,
                                              amount_paid_cents:          0,
                                              amount_remaining_cents:     1200,
                                              subscription_status:        :active,
                                              strategy_version:           3,
                                              last_attempt_id:            "pa_diag",
                                              last_attempt_number:        1,
                                              last_attempt_status:        :failed,
                                              last_failure_category:      :soft_decline,
                                              selected_step_key:          step_75pct.key,
                                              selected_percentage:        75,
                                              selected_basis:             :invoice_total,
                                              selected_payment_method_id: "pm_primary",
                                              calculated_amount_cents:    900,
                                              capped_amount_cents:        900)
    end
  end

  describe "#next_plan trace and recording" do
    it "records trace entries when requested" do
      initial_attempt = build_attempt(attempt_number: 1, failure_category: :soft_decline)

      decision = strategy.next_plan(build_context(attempts: [ initial_attempt ], payment_methods: [ build_payment_method ]), now: now, trace: true)

      expect(decision.trace).not_to be_empty
      expect(decision.trace.map { |entry| entry.fetch(:branch) }).to include(:candidate_steps, :payment_method_selection, :amount_calculation)
    end

    it "does not record trace entries by default" do
      initial_attempt = build_attempt(attempt_number: 1, failure_category: :soft_decline)

      decision = strategy.next_plan(build_context(attempts: [ initial_attempt ], payment_methods: [ build_payment_method ]), now: now)

      expect(decision.trace).to eq([])
    end

    it "records decisions through the configured recorder" do
      recorder = instance_spy(Rebilling::DecisionRecorder)
      recording_strategy = described_class.new(steps: [ step_75pct ], decision_recorder: recorder)
      strategy_context = build_context(attempts: [ build_attempt(attempt_number: 1, failure_category: :soft_decline) ], payment_methods: [ build_payment_method ])

      decision = recording_strategy.next_plan(strategy_context, now: now)

      expect(recorder).to have_received(:record).with(strategy_context, decision)
    end
  end
end
