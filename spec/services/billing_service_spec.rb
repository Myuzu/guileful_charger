require "rails_helper"

RSpec.describe BillingService, type: :service do
  describe ".call" do
    let(:payment_attempt) { FactoryBot.create(:payment_attempt) }
    let(:payload) do
      { payment_attempt_id: payment_attempt.id,
        subscription_id:    payment_attempt.subscription.id }
    end

    before do
      allow(Hutch).to receive(:publish)
    end

    it "publishes the payment attempt payload expected by billing consumers" do
      described_class.call(payment_attempt)

      expect(Hutch).to have_received(:publish).with("billing.attempt.new", payload)
    end
  end
end
