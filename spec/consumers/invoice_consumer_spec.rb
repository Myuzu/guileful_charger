require "rails_helper"

RSpec.describe InvoiceConsumer, type: :consumer do
  describe "#process" do
    before do
      allow(Hutch).to receive(:publish)
    end

    context "with draft Invoice" do
      let(:drafted_invoice) { FactoryBot.create(:invoice) }

      let(:properties) do
        instance_double(Hutch::Message::Properties, content_type: "application/json",
                                                    message_id:   SecureRandom.uuid,
                                                    timestamp:    Time.current)
      end

      it "opens Invoice and queue for `billing.attempt.new`" do
        skip "This test requires a more comprehensive integration test setup and is currently pending."
        message = Hutch::Message.new(instance_double(Hutch::Message::DeliveryInfo, routing_key: "invoice.created"),
                                     properties,
                                     { invoice_id: drafted_invoice.id }.with_indifferent_access.to_json,
                                     Hutch::Config[:serializer])
        # expect {
        #   described_class.new.process(message)
        # }.to call(Hutch.publish)
      end
    end
  end
end
