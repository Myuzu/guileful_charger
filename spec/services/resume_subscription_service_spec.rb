# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe ResumeSubscriptionService, type: :service do
  describe ".call" do
    it "resumes a paused subscription" do
      subscription = FactoryBot.create(:subscription, :paused)

      result = described_class.call(subscription, reason: "customer requested resume")

      expect(result).to be_success
      expect(subscription.reload).to be_active
      expect(subscription.resume_reason).to eq("customer requested resume")
    end

    it "extends the current period by the pause duration" do
      now = Time.current
      paused_at = 2.days.ago
      current_period_end = 1.week.from_now
      subscription = FactoryBot.create(:subscription, :paused,
                                       paused_at:          paused_at,
                                       current_period_end: current_period_end)

      allow(Time).to receive(:current).and_return(now)

      described_class.call(subscription, reason: "customer requested resume")

      expect(subscription.reload.current_period_end.to_i).to eq((current_period_end + (now - paused_at)).to_i)
      expect(subscription.active_at).to be_within(1.second).of(now)
    end

    it "re-enqueues scheduled payment attempts" do
      subscription = FactoryBot.create(:subscription, :paused)
      invoice = FactoryBot.create(:invoice, subscription: subscription)
      payment_attempt = FactoryBot.create(:payment_attempt, :scheduled, invoice: invoice)

      described_class.call(subscription, reason: "customer requested resume")

      outbox_message = OutboxMessage.find_by!(topic: "billing.attempt.new")
      expect(outbox_message.payload["payment_attempt_id"]).to eq(payment_attempt.id)
      expect(outbox_message.payload["subscription_state_version"]).to eq(subscription.reload.state_version)
    end

    it "is idempotent when the subscription is already active" do
      subscription = FactoryBot.create(:subscription)

      result = described_class.call(subscription, reason: "duplicate resume")

      expect(result).to be_success
      expect(subscription.reload.resume_reason).to be_nil
    end

    it "rejects cancelled subscriptions" do
      subscription = FactoryBot.create(:subscription, :cancelled)

      result = described_class.call(subscription, reason: "too late")

      expect(result).to be_failure
      expect(result.failure.first).to eq(:already_cancelled)
    end
  end
end
