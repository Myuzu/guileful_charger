# rubocop:disable RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe BillingService, type: :service do
  describe ".call" do
    let(:payment_attempt) { create(:payment_attempt) }
    let(:payload) do
      { payment_attempt_id:         payment_attempt.id,
        subscription_id:            payment_attempt.subscription.id,
        subscription_state_version: payment_attempt.subscription.state_version }
    end

    it "records the payment attempt payload expected by billing consumers" do
      described_class.call(payment_attempt)

      outbox_message = OutboxMessage.find_by!(topic: "billing.attempt.new")
      expect(outbox_message.payload).to eq(payload.stringify_keys)
    end
  end
end
