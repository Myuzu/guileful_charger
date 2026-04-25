require "rails_helper"

RSpec.describe BillingProcessorConsumer, type: :consumer do
  describe "#find_payment_attempt" do
    let(:payment_attempt) { FactoryBot.create(:payment_attempt) }
    let(:message) { instance_double(Hutch::Message, body: { payment_attempt_id: payment_attempt.id }) }

    it "finds the payment attempt from the message payload" do
      expect(described_class.new.send(:find_payment_attempt, message)).to eq(payment_attempt)
    end
  end
end
