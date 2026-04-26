# rubocop:disable RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe RetryManagerConsumer, type: :consumer do
  describe "#process" do
    it "acks rule-invalid payloads and records an invalid-payload event" do
      message = instance_double(Hutch::Message, body: {}, message_id: SecureRandom.uuid)

      described_class.new.process(message)

      outbox_message = OutboxMessage.find_by!(topic: "billing.consumer.invalid_payload")
      expect(outbox_message.payload["consumer_name"]).to eq("RetryManagerConsumer")
      expect(outbox_message.payload["errors"].values.flatten).to include("must include payment_attempt_id or subscription_id")
    end
  end
end
