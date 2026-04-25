# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe OutboxPublisherService, type: :service do
  describe ".call" do
    let(:payload) { { subscription_id: SecureRandom.uuid, event: "test" } }
    let(:outbox_message) { OutboxMessage.create!(topic: "subscription.paused", payload: payload) }

    before do
      OutboxMessage.delete_all
      outbox_message
      allow(Hutch).to receive(:publish)
      allow(RabbitMqTopology).to receive(:publish_to_consistent_hash)
    end

    it "publishes unpublished messages and marks them published" do
      described_class.call(batch_size: 1)

      expect(Hutch).to have_received(:publish).with("subscription.paused", payload.stringify_keys, { message_id: outbox_message.id })
      expect(RabbitMqTopology).to have_received(:publish_to_consistent_hash)
      expect(outbox_message.reload.published_at).to be_present
      expect(outbox_message.locked_at).to be_nil
      expect(outbox_message.attempts).to eq(1)
    end

    it "records publish failures and leaves the message unpublished" do
      allow(Hutch).to receive(:publish).and_raise(Hutch::ConnectionError)

      described_class.call(batch_size: 1)

      expect(outbox_message.reload.published_at).to be_nil
      expect(outbox_message.locked_at).to be_nil
      expect(outbox_message.attempts).to eq(1)
      expect(outbox_message.last_error).to be_present
    end

    it "treats consistent-hash mirror failures as best effort" do
      allow(RabbitMqTopology).to receive(:publish_to_consistent_hash).and_raise(StandardError, "mirror unavailable")

      described_class.call(batch_size: 1)

      expect(outbox_message.reload.published_at).to be_present
      expect(outbox_message.last_error).to be_nil
    end

    it "does not publish recently locked messages" do
      outbox_message.update!(locked_at: Time.current)

      described_class.call(batch_size: 1)

      expect(Hutch).not_to have_received(:publish)
    end

    it "reclaims stale locked messages" do
      outbox_message.update!(locked_at: 1.hour.ago)

      described_class.call(batch_size: 1)

      expect(Hutch).to have_received(:publish)
    end
  end
end
