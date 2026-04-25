# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe PauseSubscriptionService, type: :service do
  describe ".call" do
    it "pauses an active subscription and records a versioned outbox event" do
      subscription = FactoryBot.create(:subscription)

      result = described_class.call(subscription, reason: "customer requested pause")
      outbox_message = OutboxMessage.find_by!(topic: "subscription.paused")

      expect(result).to be_success
      expect(subscription.reload).to be_paused
      expect(subscription.pause_reason).to eq("customer requested pause")
      expect(outbox_message.payload["state_version"]).to eq(subscription.state_version)
    end

    it "is idempotent when the subscription is already paused" do
      subscription = FactoryBot.create(:subscription, :paused)
      original_paused_at = subscription.paused_at
      original_state_version = subscription.state_version

      result = described_class.call(subscription, reason: "duplicate pause")

      expect(result).to be_success
      expect(subscription.reload.pause_reason).to eq("customer requested pause")
      expect(subscription.paused_at).to eq(original_paused_at)
      expect(subscription.state_version).to eq(original_state_version)
    end

    it "rejects cancelled subscriptions" do
      subscription = FactoryBot.create(:subscription, :cancelled)

      result = described_class.call(subscription, reason: "too late")

      expect(result).to be_failure
      expect(result.failure.first).to eq(:already_cancelled)
    end

    it "removes unstarted current-period draft invoices" do
      subscription = FactoryBot.create(:subscription)
      invoice = FactoryBot.create(:invoice,
                                  subscription:         subscription,
                                  billing_period_start: subscription.current_period_start,
                                  billing_period_end:   subscription.current_period_end)

      described_class.call(subscription, reason: "customer requested pause")

      expect(Invoice.exists?(invoice.id)).to be(false)
    end
  end
end
