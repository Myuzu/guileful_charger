# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe CancelSubscriptionService, type: :service do
  describe ".call" do
    it "cancels an active subscription and records a versioned outbox event" do
      subscription = FactoryBot.create(:subscription)

      result = described_class.call(subscription, reason: "customer requested cancellation")
      outbox_message = OutboxMessage.find_by!(topic: "subscription.cancelled")

      expect(result).to be_success
      expect(subscription.reload).to be_cancelled
      expect(subscription.cancellation_reason).to eq("customer requested cancellation")
      expect(outbox_message.payload["subscription_id"]).to eq(subscription.id)
      expect(outbox_message.payload["state_version"]).to eq(subscription.state_version)
    end

    it "cancels a paused subscription" do
      subscription = FactoryBot.create(:subscription, :paused)

      result = described_class.call(subscription, reason: "customer requested cancellation")

      expect(result).to be_success
      expect(subscription.reload).to be_cancelled
    end

    it "is idempotent when the subscription is already cancelled" do
      subscription = FactoryBot.create(:subscription, :cancelled)
      original_state_version = subscription.state_version

      result = described_class.call(subscription, reason: "duplicate cancellation")

      expect(result).to be_success
      expect(subscription.reload.cancellation_reason).to eq("customer requested cancellation")
      expect(subscription.state_version).to eq(original_state_version)
    end

    it "does not clean up invoices or payment attempts" do
      subscription = FactoryBot.create(:subscription)
      invoice = FactoryBot.create(:invoice,
                                  subscription:         subscription,
                                  billing_period_start: subscription.current_period_start,
                                  billing_period_end:   subscription.current_period_end)
      payment_attempt = FactoryBot.create(:payment_attempt, invoice: invoice)

      described_class.call(subscription, reason: "customer requested cancellation")

      expect(Invoice.exists?(invoice.id)).to be(true)
      expect(PaymentAttempt.exists?(payment_attempt.id)).to be(true)
    end

    it "rejects invalid command input" do
      subscription = FactoryBot.create(:subscription)

      result = described_class.call(subscription, reason: 123)

      expect(result).to be_failure
      expect(result.failure.first).to eq(:invalid_input)
      expect(result.failure.last.fetch(:errors)).to include(:reason)
    end
  end
end
