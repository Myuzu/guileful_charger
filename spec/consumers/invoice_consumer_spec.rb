require "rails_helper"

RSpec.describe InvoiceConsumer, type: :consumer do
  describe "#process" do
    before do
      allow(Hutch).to receive(:publish)
    end

    context "with draft Invoice" do
      let(:drafted_invoice) { FactoryBot.create(:invoice) }
      let(:message) { instance_double(Hutch::Message, body: { invoice_id: drafted_invoice.id }) }
      let(:payment_attempt) { drafted_invoice.payment_attempts.first }
      let(:expected_payload) { { payment_attempt_id: payment_attempt.id } }

      it "opens the invoice" do
        described_class.new.process(message)

        expect(drafted_invoice.reload).to be_open
      end

      it "schedules the created payment attempt" do
        described_class.new.process(message)

        expect(drafted_invoice.payment_attempts.first).to be_scheduled
      end

      it "publishes the created payment attempt for processing" do
        described_class.new.process(message)

        expect(Hutch).to have_received(:publish).with("billing.attempt.new", expected_payload)
      end
    end
  end
end
