# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe ConsumerIdempotency do
  subject(:consumer) { consumer_class.new }

  let(:consumer_class) do
    Class.new do
      include ConsumerIdempotency

      attr_reader :processed_count

      def self.name = "TestConsumer"

      def initialize
        @processed_count = 0
      end

      def process(message)
        process_once(message) { @processed_count += 1 }
      end

      def logger = Rails.logger
    end
  end

  let(:message) { instance_double(Hutch::Message, body: { event: "test" }, message_id: "message-1") }

  it "processes a message once" do
    consumer.process(message)

    expect(consumer.processed_count).to eq(1)
    expect(ProcessedMessage.exists?(consumer_name: "TestConsumer", message_id: "message-1")).to be(true)
  end

  it "skips duplicate messages" do
    consumer.process(message)
    consumer.process(message)

    expect(consumer.processed_count).to eq(1)
  end

  it "releases the idempotency claim when processing fails" do
    failing_consumer = Class.new(consumer_class) do
      def process(message)
        process_once(message) { raise "boom" }
      end
    end.new

    expect { failing_consumer.process(message) }.to raise_error(RuntimeError, "boom")
    expect(ProcessedMessage.exists?(consumer_name: "TestConsumer", message_id: "message-1")).to be(false)
  end

  it "falls back to a body digest when message_id is missing" do
    message_without_id = instance_double(Hutch::Message, body: { event: "test" }, message_id: nil)

    consumer.process(message_without_id)

    expect(ProcessedMessage.last.message_id).to eq(Digest::SHA256.hexdigest("TestConsumer:{\"event\":\"test\"}"))
  end
end
