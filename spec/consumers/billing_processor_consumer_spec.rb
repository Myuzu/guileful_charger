# rubocop:disable RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe BillingProcessorConsumer, type: :consumer do
  describe "#find_payment_attempt" do
    let(:payment_attempt) { FactoryBot.create(:payment_attempt) }

    it "finds the payment attempt from the validated payload" do
      expect(described_class.new.send(:find_payment_attempt, payment_attempt_id: payment_attempt.id)).to eq(payment_attempt)
    end
  end

  describe "#process" do
    let(:message) do
      instance_double(Hutch::Message,
                      body:       { payment_attempt_id: payment_attempt.id },
                      message_id: SecureRandom.uuid)
    end

    context "with an active subscription and scheduled payment attempt" do
      let(:payment_attempt) { FactoryBot.create(:payment_attempt, :scheduled, amount_attempted_cents: 500) }

      it "processes the payment attempt and records a success outbox message" do
        described_class.new.process(message)

        expect(payment_attempt.reload).to be_completed
        expect(OutboxMessage.last.topic).to eq("billing.payment.full.success")
      end
    end

    context "with an invalid payload" do
      let(:payment_attempt) { FactoryBot.create(:payment_attempt, :scheduled, amount_attempted_cents: 500) }
      let(:message) do
        instance_double(Hutch::Message,
                        body:       { subscription_id: payment_attempt.subscription.id },
                        message_id: SecureRandom.uuid)
      end

      it "acks the malformed message without processing a payment" do
        described_class.new.process(message)

        expect(payment_attempt.reload).to be_scheduled
        expect(OutboxMessage.where(topic: "billing.payment.full.success")).to be_empty
      end
    end

    context "with a paused subscription" do
      let(:subscription) { FactoryBot.create(:subscription, :paused) }
      let(:invoice) { FactoryBot.create(:invoice, subscription: subscription) }
      let(:payment_attempt) { FactoryBot.create(:payment_attempt, :scheduled, invoice: invoice) }

      it "does not process the payment attempt and records a skipped event" do
        described_class.new.process(message)

        outbox_message = OutboxMessage.find_by!(topic: "billing.payment.skipped")
        expect(payment_attempt.reload).to be_scheduled
        expect(outbox_message.payload["skipped_reason"]).to eq("subscription_not_active")
      end
    end

    context "with a pending payment attempt" do
      let(:payment_attempt) { FactoryBot.create(:payment_attempt) }

      it "records a skipped event" do
        described_class.new.process(message)

        outbox_message = OutboxMessage.find_by!(topic: "billing.payment.skipped")
        expect(outbox_message.payload["skipped_reason"]).to eq("not_scheduled")
      end
    end

    context "with insufficient funds" do
      let(:payment_attempt) { FactoryBot.create(:payment_attempt, :scheduled, amount_attempted_cents: 1500) }

      it "records a failed payment event without raising" do
        described_class.new.process(message)

        outbox_message = OutboxMessage.find_by!(topic: "billing.payment.failed")
        expect(payment_attempt.reload).to be_failed
        expect(outbox_message.payload["failure_reason"]).to eq("insufficient_funds")
      end
    end

    context "with a retryable system error" do
      let(:payment_attempt) { FactoryBot.create(:payment_attempt, :scheduled, amount_attempted_cents: 0) }

      it "records a failed payment event and raises for broker retry/dead-letter handling" do
        expect {
          described_class.new.process(message)
        }.to raise_error(BillingProcessorConsumer::PaymentProcessingRetryableError)

        outbox_message = OutboxMessage.find_by!(topic: "billing.payment.failed")
        expect(outbox_message.payload["failure_reason"]).to eq("system_error")
      end
    end
  end
end
