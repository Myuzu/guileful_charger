# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe Rebilling::RetryStep do
  let(:context) do
    Rebilling::Context.new(invoice_id:            "inv_123",
                           invoice_status:        :partially_paid,
                           invoice_total_cents:   1200,
                           amount_paid_cents:     900,
                           subscription_status:   :active)
  end

  describe "generated key" do
    it "includes percentage, basis, and delay" do
      step = described_class.new(percentage: 25, delay: 5.minutes)

      expect(step.key).to eq(:charge_25pct_invoice_total_after_300s)
    end

    it "distinguishes the same percentage with different delays" do
      slow_step = described_class.new(percentage: 25, delay: 5.minutes)
      fast_step = described_class.new(percentage: 25, delay: 1.minute)

      expect(slow_step.key).not_to eq(fast_step.key)
    end

    it "falls back to the generated key when an explicit key is blank" do
      step = described_class.new(percentage: 25, delay: 5.minutes, key: "")

      expect(step.key).to eq(:charge_25pct_invoice_total_after_300s)
    end

    it "normalizes float percentages in generated keys" do
      step = described_class.new(percentage: 12.5, delay: 5.minutes)

      expect(step.key).to eq(:charge_12_5pct_invoice_total_after_300s)
    end
  end

  describe "amount calculation" do
    it "uses invoice total by default and caps by remaining balance" do
      step = described_class.new(percentage: 75, delay: 1.day)

      calculation = step.amount_calculation_for(context)

      expect(calculation.base_cents).to eq(1200)
      expect(calculation.calculated_amount_cents).to eq(900)
      expect(calculation.capped_amount_cents).to eq(300)
    end

    it "can calculate from remaining balance" do
      step = described_class.new(percentage: 50, basis: :remaining_balance, delay: 1.day)

      expect(step.amount_for(context)).to eq(150)
    end
  end

  describe "retry window" do
    it "returns a deterministic retry time inside the retry window" do
      now = Time.zone.parse("2026-01-01 12:00:00 UTC")
      step = described_class.new(percentage: 25, delay: 5.minutes, jitter: 0..120.seconds)

      window = step.retry_window(now: now, context: context, attempt_number: 4)

      expect(window.fetch(:earliest_retry_at)).to eq(now + 5.minutes)
      expect(window.fetch(:latest_retry_at)).to eq(now + 7.minutes)
      expect(window.fetch(:retry_at)).to be_between(window.fetch(:earliest_retry_at), window.fetch(:latest_retry_at)).inclusive
      expect(step.retry_window(now: now, context: context, attempt_number: 4)).to eq(window)
    end

    it "sets retry_at equal to the exact window when jitter is zero" do
      now = Time.zone.parse("2026-01-01 12:00:00 UTC")
      step = described_class.new(percentage: 25, delay: 5.minutes)

      window = step.retry_window(now: now, context: context, attempt_number: 4)

      expect(window.fetch(:retry_at)).to eq(window.fetch(:earliest_retry_at))
      expect(window.fetch(:retry_at)).to eq(window.fetch(:latest_retry_at))
    end

    it "honors non-zero jitter lower bounds" do
      now = Time.zone.parse("2026-01-01 12:00:00 UTC")
      step = described_class.new(percentage: 25, delay: 5.minutes, jitter: 30..60.seconds)

      window = step.retry_window(now: now, context: context, attempt_number: 4)

      expect(window.fetch(:earliest_retry_at)).to eq(now + 5.minutes + 30.seconds)
      expect(window.fetch(:latest_retry_at)).to eq(now + 6.minutes)
      expect(window.fetch(:retry_at)).to be_between(window.fetch(:earliest_retry_at), window.fetch(:latest_retry_at)).inclusive
    end
  end

  describe "validation" do
    it "rejects invalid percentages" do
      aggregate_failures do
        expect { described_class.new(percentage: 0, delay: 1.day) }.to raise_error(ArgumentError, /percentage must be greater than 0/)
        expect { described_class.new(percentage: 101, delay: 1.day) }.to raise_error(ArgumentError, /percentage must be less than or equal to 100/)
      end
    end

    it "rejects invalid basis and transitions" do
      aggregate_failures do
        expect { described_class.new(percentage: 25, basis: :unknown, delay: 1.day) }.to raise_error(ArgumentError, /basis must be one of/)
        expect { described_class.new(percentage: 25, delay: 1.day, on_success: :jump) }.to raise_error(ArgumentError, /transition must be one of/)
      end
    end
  end
end
