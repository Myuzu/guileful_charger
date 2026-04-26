module ActiveConsumer
  extend ActiveSupport::Concern

  class ConsumerOptionsBuilder
    DEFAULT_DEAD_LETTER_EXCHANGE = "billing.events.dlx".freeze
    DEFAULT_DELIVERY_LIMIT = 5

    def initialize(consumer)
      @consumer = consumer
      @arguments = {}
    end

    def quorum_queue(**options)
      options.any? ? @consumer.quorum_queue(options) : @consumer.quorum_queue
    end

    def dead_letter(routing_key:, exchange: DEFAULT_DEAD_LETTER_EXCHANGE)
      @arguments["x-dead-letter-exchange"] = exchange
      @arguments["x-dead-letter-routing-key"] = routing_key
    end

    def delivery_limit(value = DEFAULT_DELIVERY_LIMIT)
      @arguments["x-delivery-limit"] = value
    end

    def single_active_consumer(value = true)
      @arguments["x-single-active-consumer"] = value
    end

    def arguments(values)
      @arguments.merge!(values)
    end

    def apply!
      @consumer.arguments(@arguments) if @arguments.any?
    end
  end

  included do
    include Hutch::Consumer
    include ConsumerIdempotency
  end

  class_methods do
    def consumer_options(&block)
      builder = ConsumerOptionsBuilder.new(self)
      builder.instance_eval(&block)
      builder.apply!
    end

    def message_schema(&block)
      @message_schema_block = block
      @message_contract = nil
    end

    def message_rule(*keys, &block)
      message_rules << [ keys, block ]
      @message_contract = nil
    end

    def message_rules
      @message_rules ||= []
    end

    def message_contract
      @message_contract ||= build_message_contract
    end

    private

    def build_message_contract
      schema_block = @message_schema_block
      rules = message_rules

      Class.new(Dry::Validation::Contract) do
        params(&schema_block) if schema_block

        rules.each do |keys, rule_block|
          rule(*keys, &rule_block)
        end
      end.new
    end
  end

  def process(message)
    process_once(message) do
      payload = validate_message_payload(message)
      process_message(message, payload) if payload
    end
  end

  private

  def validate_message_payload(message)
    result = self.class.message_contract.call(message.body)
    return result.to_h if result.success?

    record_invalid_payload(message, result.errors.to_h)
    nil
  end

  def record_invalid_payload(message, errors)
    payload = { consumer_name: self.class.name,
                message_id:     idempotency_message_id(message),
                errors:         errors,
                body:           message.body }

    logger.warn("Ignoring invalid #{self.class.name} payload: #{payload.to_json}")
    OutboxMessage.enqueue!(topic: "billing.consumer.invalid_payload", payload: payload)
  rescue StandardError => ex
    # Invalid payloads are poison messages: retrying them will not make them valid.
    # Preserve broker liveness by ACKing them even if the best-effort observability
    # event cannot be recorded during a database outage.
    logger.error("Failed to record invalid #{self.class.name} payload: #{ex.class}: #{ex.message}")
  end
end
