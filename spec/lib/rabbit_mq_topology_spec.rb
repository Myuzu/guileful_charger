# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/VerifiedDoubles
require "rails_helper"

RSpec.describe RabbitMqTopology do
  describe "#declare!" do
    let(:channel) { double("Channel") }
    let(:exchange) { double("Exchange") }
    let(:queue) { double("Queue", bind: true) }

    before do
      allow(channel).to receive_messages(exchange: exchange, queue: queue)
    end

    it "declares exchanges, retry queues, dead-letter queues, and hash shards" do
      described_class.new(channel).declare!

      expect(channel).to have_received(:exchange).with(described_class::MAIN_EXCHANGE, type: :topic, durable: true).at_least(:once)
      expect(channel).to have_received(:exchange).with(described_class::DEAD_LETTER_EXCHANGE, type: :topic, durable: true).at_least(:once)
      expect(channel).to have_received(:exchange).with(described_class::RETRY_EXCHANGE, type: :topic, durable: true).at_least(:once)
      expect(channel).to have_received(:exchange).with(described_class::HASH_EXCHANGE, type: "x-consistent-hash", durable: true).at_least(:once)
      expect(channel).to have_received(:queue).at_least(:once)
      expect(queue).to have_received(:bind).at_least(:once)
    end
  end

  describe ".publish_to_consistent_hash" do
    let(:channel) { double("Channel") }
    let(:broker) { double("Broker", channel: channel) }
    let(:exchange) { double("Exchange", publish: true) }

    before do
      allow(Hutch).to receive(:broker).and_return(broker)
      allow(channel).to receive(:exchange).and_return(exchange)
    end

    it "publishes a persistent JSON message using subscription_id as routing key" do
      described_class.publish_to_consistent_hash(topic:           "subscription.paused",
                                                 payload:          { subscription_id: "sub-1" },
                                                 subscription_id:  "sub-1",
                                                 message_id:       "message-1")

      expect(exchange).to have_received(:publish).with(
        { subscription_id: "sub-1" }.to_json,
        hash_including(routing_key: "sub-1", persistent: true, message_id: "message-1")
      )
    end
  end
end
