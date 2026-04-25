# rubocop:disable RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe InvoiceConsumer, type: :consumer do
  describe "#process" do
    context "with draft Invoice" do
      let(:drafted_invoice) { FactoryBot.create(:invoice) }
      let(:message) do
        instance_double(Hutch::Message,
                        body:       { invoice_id: drafted_invoice.id },
                        message_id: SecureRandom.uuid)
      end
      let(:payment_attempt) { drafted_invoice.payment_attempts.first }
      let(:expected_payload) do
        { payment_attempt_id:         payment_attempt.id,
          subscription_id:            drafted_invoice.subscription_id,
          subscription_state_version: drafted_invoice.subscription.state_version }
      end

      it "opens the invoice" do
        described_class.new.process(message)

        expect(drafted_invoice.reload).to be_open
      end

      it "schedules the created payment attempt" do
        described_class.new.process(message)

        expect(drafted_invoice.payment_attempts.first).to be_scheduled
      end

      it "records an outbox message for processing the payment attempt" do
        described_class.new.process(message)

        outbox_message = OutboxMessage.find_by!(topic: "billing.attempt.new")
        expect(outbox_message.payload).to eq(expected_payload.stringify_keys)
      end

      it "does not open invoices for paused subscriptions" do
        drafted_invoice.subscription.pause!("customer requested pause")

        described_class.new.process(message)

        expect(drafted_invoice.reload).to be_draft
        expect(OutboxMessage.where(topic: "billing.attempt.new")).to be_empty
      end
    end
  end
end
