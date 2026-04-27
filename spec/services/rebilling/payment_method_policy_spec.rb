# rubocop:disable RSpec/ExampleLength
require "rails_helper"

RSpec.describe Rebilling::PaymentMethodPolicy do
  include RebillingHelpers

  let(:step) { Rebilling::RetryStep.new(percentage: 25, delay: 1.minute) }
  let(:policy) { described_class.default }

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
end
