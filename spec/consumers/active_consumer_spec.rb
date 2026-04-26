# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe ActiveConsumer do
  subject(:consumer) { consumer_class.new }

  let(:consumer_class) do
    Class.new do
      include ActiveConsumer

      attr_reader :processed_payload

      def self.name = "SchemaConsumer"

      message_schema do
        required(:event_id).filled(:string)
        optional(:state_version).maybe(:integer)
      end

      private

      def process_message(_message, payload)
        @processed_payload = payload
      end
    end
  end

  it "validates and passes coerced payloads to process_message" do
    message = instance_double(Hutch::Message,
                              body:       { event_id: "event-1", state_version: "2" },
                              message_id: "message-1")

    consumer.process(message)

    expect(consumer.processed_payload).to eq(event_id: "event-1", state_version: 2)
    expect(ProcessedMessage.exists?(consumer_name: "SchemaConsumer", message_id: "message-1")).to be(true)
  end

  it "acks invalid payloads without calling process_message and records an invalid-payload event" do
    message = instance_double(Hutch::Message,
                              body:       { state_version: "2" },
                              message_id: "message-2")

    consumer.process(message)

    outbox_message = OutboxMessage.find_by!(topic: "billing.consumer.invalid_payload")
    expect(consumer.processed_payload).to be_nil
    expect(ProcessedMessage.exists?(consumer_name: "SchemaConsumer", message_id: "message-2")).to be(true)
    expect(outbox_message.payload["consumer_name"]).to eq("SchemaConsumer")
  end

  it "declares Hutch queue options with a consumer_options block" do
    options_consumer = Class.new do
      include ActiveConsumer

      def self.name = "OptionsConsumer"

      consumer_options do
        quorum_queue
        dead_letter routing_key: "events.dead"
        delivery_limit
        single_active_consumer
      end
    end

    expect(options_consumer.get_arguments).to include("x-queue-type" => "quorum",
                                                      "x-dead-letter-exchange" => "billing.events.dlx",
                                                      "x-dead-letter-routing-key" => "events.dead",
                                                      "x-delivery-limit" => 5,
                                                      "x-single-active-consumer" => true)
  end

  it "supports consumer-level message rules" do
    rule_consumer = Class.new do
      include ActiveConsumer

      attr_reader :processed_payload

      def self.name = "RuleConsumer"

      message_schema do
        optional(:payment_attempt_id).filled(:string)
        optional(:subscription_id).filled(:string)
      end

      message_rule do
        next if values[:payment_attempt_id] || values[:subscription_id]

        base.failure("must include payment_attempt_id or subscription_id")
      end

      private

      def process_message(_message, payload)
        @processed_payload = payload
      end
    end.new

    message = instance_double(Hutch::Message, body: {}, message_id: "message-3")

    rule_consumer.process(message)

    outbox_message = OutboxMessage.find_by!(topic: "billing.consumer.invalid_payload")
    expect(rule_consumer.processed_payload).to be_nil
    expect(ProcessedMessage.exists?(consumer_name: "RuleConsumer", message_id: "message-3")).to be(true)
    expect(outbox_message.payload["consumer_name"]).to eq("RuleConsumer")
  end
end
