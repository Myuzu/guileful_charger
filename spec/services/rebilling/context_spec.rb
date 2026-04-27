# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe Rebilling::Context do
  include RebillingHelpers

  it "is paid when status is paid or remaining balance is zero" do
    aggregate_failures do
      expect(build_context(invoice_status: :paid)).to be_paid
      expect(build_context(amount_paid_cents: 1200)).to be_paid
    end
  end

  it "detects retryable invoice statuses" do
    aggregate_failures do
      expect(build_context(invoice_status: :open)).to be_retryable_invoice
      expect(build_context(invoice_status: :partially_paid)).to be_retryable_invoice
      expect(build_context(invoice_status: :not_paid)).not_to be_retryable_invoice
    end
  end

  it "selects the latest terminal attempt by attempt number" do
    first = build_attempt(id: "pa_1", attempt_number: 1, status: :failed)
    second = build_attempt(id: "pa_3", attempt_number: 3, status: :completed)
    in_flight = build_attempt(id: "pa_4", attempt_number: 4, status: :processing)

    expect(build_context(attempts: [ first, second, in_flight ]).latest_terminal_attempt).to eq(second)
  end

  it "detects all in-flight statuses" do
    aggregate_failures do
      %i[pending scheduled processing].each do |status|
        expect(build_context(attempts: [ build_attempt(id: "pa_#{status}", attempt_number: 1, status: status) ])).to be_in_flight_attempt
      end
    end
  end

  it "finds attempts for a step using symbol or string keys" do
    matching = build_attempt(id: "pa_1", attempt_number: 1, status: :failed, retry_step_key: :charge_25)
    other = build_attempt(id: "pa_2", attempt_number: 2, status: :failed, retry_step_key: :charge_15)

    expect(build_context(attempts: [ matching, other ]).attempts_for_step("charge_25")).to eq([ matching ])
  end

  it "rejects negative amounts" do
    aggregate_failures do
      expect { build_context(amount_paid_cents: -1) }.to raise_error(Dry::Types::CoercionError, /integer must be greater than or equal to 0/)
      expect { build_context(invoice_total_cents: -1) }.to raise_error(Dry::Types::CoercionError, /integer must be greater than or equal to 0/)
    end
  end

  it "clamps amount_remaining_cents to zero on overpayment" do
    expect(build_context(amount_paid_cents: 1500).amount_remaining_cents).to eq(0)
  end

  it "returns zero from latest_attempt_number when there are no attempts" do
    expect(build_context.latest_attempt_number).to eq(0)
  end

  it "exposes a stable to_h observability snapshot" do
    context = build_context(invoice_status:    :partially_paid,
                            amount_paid_cents: 300,
                            customer_timezone: "Europe/Vienna",
                            metadata:          { region: "EU" })

    expect(context.to_h).to include(invoice_id:              context.invoice_id,
                                    invoice_status:          :partially_paid,
                                    invoice_total_cents:     1200,
                                    amount_paid_cents:       300,
                                    amount_remaining_cents:  900,
                                    subscription_status:     :active,
                                    customer_timezone:       "Europe/Vienna",
                                    metadata:                { region: "EU" })
  end
end
