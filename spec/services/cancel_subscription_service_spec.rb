# rubocop:disable RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe CancelSubscriptionService, type: :service do
  describe ".call" do
    it "cancels an active subscription" do
      subscription = FactoryBot.create(:subscription)

      result = described_class.call(subscription, reason: "customer requested cancellation")

      expect(result).to be_success
      expect(subscription.reload).to be_cancelled
      expect(subscription.cancellation_reason).to eq("customer requested cancellation")
    end

    it "cancels a paused subscription" do
      subscription = FactoryBot.create(:subscription, :paused)

      result = described_class.call(subscription, reason: "customer requested cancellation")

      expect(result).to be_success
      expect(subscription.reload).to be_cancelled
    end

    it "is idempotent when the subscription is already cancelled" do
      subscription = FactoryBot.create(:subscription, :cancelled)

      result = described_class.call(subscription, reason: "duplicate cancellation")

      expect(result).to be_success
      expect(subscription.reload.cancellation_reason).to eq("customer requested cancellation")
    end
  end
end
