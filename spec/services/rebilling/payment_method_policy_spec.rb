# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe Rebilling::PaymentMethodPolicy do
  include RebillingHelpers

  let(:step) { Rebilling::RetryStep.new(percentage: 25, delay: 1.minute) }
  let(:policy) { described_class.default }

  it "preserves normalized defaults, flags, and immutability" do
    configured = described_class.new(order: "primary_then_recent_success", exhaust_methods_per_step: false)

    expect(configured.order).to eq(:primary_then_recent_success)
    expect(configured).not_to be_exhaust_methods_per_step
    expect(policy).to be_exhaust_methods_per_step
    expect(configured).to be_frozen
  end

  it "preserves subclass construction through default" do
    specialized = Class.new(described_class)

    expect(specialized.default).to be_an_instance_of(specialized)
  end

  it "returns nil when there are no eligible methods, including a preferred inactive method" do
    inactive = build_payment_method("pm_inactive", status: :disabled)

    expect(policy.select(build_context, step)).to be_nil
    expect(policy.select(build_context(payment_methods: [ inactive ]), step, preferred_payment_method_id: inactive.id)).to be_nil
  end

  it "preserves integer and nil identifiers" do
    primary = build_payment_method(7, primary: true)
    backup = build_payment_method(42)
    unidentified = build_payment_method(nil)

    expect(policy.select(build_context(payment_methods: [ primary, backup ]), step, preferred_payment_method_id: 42)).to equal(backup)
    expect(policy.select(build_context(payment_methods: [ unidentified ]), step)).to equal(unidentified)
  end

  it "orders equal-priority methods by recent success and then their identifiers" do
    timestamp = Time.zone.parse("2026-01-02 12:00:00 UTC")
    undated = build_payment_method("pm_none")
    older = build_payment_method("pm_old", last_successful_at: Time.utc(2026, 1, 1))
    recent_b = build_payment_method("pm_b", last_successful_at: timestamp)
    recent_a = build_payment_method("pm_a", last_successful_at: timestamp)

    expect(policy.select(build_context(payment_methods: [ undated, older, recent_b, recent_a ]), step)).to equal(recent_a)
  end

  it "prefers the active primary payment method" do
    backup = build_payment_method("pm_backup", primary: false, last_successful_at: 1.day.ago)
    primary = build_payment_method("pm_primary", primary: true)

    expect(policy.select(build_context(payment_methods: [ backup, primary ]), step).id).to eq("pm_primary")
  end

  it "skips inactive and hard-declined methods" do
    hard_declined = build_payment_method("pm_hard", primary: true, failure_category: :hard_decline)
    expired = build_payment_method("pm_expired", status: :expired)
    backup = build_payment_method("pm_backup")

    expect(policy.select(build_context(payment_methods: [ hard_declined, expired, backup ]), step).id).to eq("pm_backup")
  end

  it "tries another eligible method for a step after one method failed" do
    failed_attempt = build_attempt(attempt_number:    2,
                                   failure_category:  :soft_decline,
                                   retry_step_key:    step.key)
    primary = build_payment_method("pm_primary", primary: true)
    backup = build_payment_method("pm_backup")

    context = build_context(attempts: [ failed_attempt ], payment_methods: [ primary, backup ])

    expect(policy.select(context, step).id).to eq("pm_backup")
  end

  it "can retry the same method after a soft decline when configured" do
    failed_attempt = build_attempt(attempt_number:    2,
                                   failure_category:  :soft_decline,
                                   retry_step_key:    step.key)
    retry_same_method_policy = described_class.new(retry_same_method_after_soft_decline: true)
    primary = build_payment_method("pm_primary", primary: true)
    backup = build_payment_method("pm_backup")

    context = build_context(attempts: [ failed_attempt ], payment_methods: [ primary, backup ])

    expect(retry_same_method_policy.select(context, step).id).to eq("pm_primary")
  end

  it "can keep hard-declined methods when configured" do
    hard_declined = build_payment_method("pm_hard", primary: true, failure_category: :hard_decline)
    backup = build_payment_method("pm_backup")
    allow_hard_decline_policy = described_class.new(skip_hard_declined_methods: false)

    context = build_context(payment_methods: [ hard_declined, backup ])

    expect(allow_hard_decline_policy.select(context, step).id).to eq("pm_hard")
  end

  it "honors a preferred payment method when it is still eligible" do
    primary = build_payment_method("pm_primary", primary: true)
    backup = build_payment_method("pm_backup")

    context = build_context(payment_methods: [ primary, backup ])

    expect(policy.select(context, step, preferred_payment_method_id: "pm_backup").id).to eq("pm_backup")
  end

  it "falls back to the first eligible candidate when the preferred method is no longer eligible" do
    primary = build_payment_method("pm_primary", primary: true)
    backup = build_payment_method("pm_backup")

    context = build_context(payment_methods: [ primary, backup ])

    expect(policy.select(context, step, preferred_payment_method_id: "pm_unknown").id).to eq("pm_primary")
  end

  it "uses the failure classifier when skipping hard-declined attempts" do
    stolen_card_attempt = build_attempt(attempt_number:  2,
                                        failure_reason:  :stolen_card,
                                        retry_step_key:  step.key)
    primary = build_payment_method("pm_primary", primary: true)
    backup = build_payment_method("pm_backup")

    context = build_context(attempts: [ stolen_card_attempt ], payment_methods: [ primary, backup ])

    expect(policy.select(context, step).id).to eq("pm_backup")
  end

  it "preserves runtime injection of a custom classifier" do
    classification = Rebilling::FailureClassification.new(category: :hard_decline, network_recommendation: nil,
      retryable: false, requires_credential_refresh: false, customer_action_required: false)
    classifier = instance_double(Rebilling::FailureClassifier, classify_attempt: classification)
    configured = described_class.new(failure_classifier: classifier)
    failed = build_attempt(payment_method_id: "pm_primary")
    primary = build_payment_method("pm_primary", primary: true)
    backup = build_payment_method("pm_backup")

    selected = configured.select(build_context(attempts: [ failed ], payment_methods: [ primary, backup ]), step,
      preferred_payment_method_id: primary.id)

    expect(selected).to equal(backup)
    expect(classifier).to have_received(:classify_attempt).with(failed)
  end

  it "leaves invalid order and boolean option errors to dry-types" do
    expect { described_class.new(order: :unknown) }.to raise_error(Dry::Types::CoercionError, /payment method order/)
    expect { described_class.new(skip_hard_declined_methods: "true") }.to raise_error(Dry::Types::ConstraintError)
  end
end
