require "rails_helper"

RSpec.describe InvoiceConsumer, type: :consumer do
  describe "#process" do
    before do
      allow(Hutch).to receive(:publish)
    end

    context "with draft Invoice" do
      let(:drafted_invoice) { FactoryBot.create(:invoice) }

      let(:properties) do
        double('Properties', content_type: "application/json",
                             message_id:   SecureRandom.uuid,
                             timestamp:    Time.current)
      end

      xit "opens Invoice and queue for `billing.attempt.new`" do
        message = Hutch::Message.new(double('Delivery Info', routing_key: "invoice.created"),
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
