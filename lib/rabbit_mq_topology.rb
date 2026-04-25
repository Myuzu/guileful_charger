class RabbitMqTopology
  MAIN_EXCHANGE = "billing.events".freeze
  DEAD_LETTER_EXCHANGE = "billing.events.dlx".freeze
  HASH_EXCHANGE = "billing.events.by_subscription".freeze
  RETRY_EXCHANGE = "billing.events.retry".freeze
  DEAD_LETTER_ROUTING_KEYS = %w[
    billing.attempt.dead
    billing.payment.skipped.dead
    invoice.created.dead
    billing.notification.dead
    billing.retry.dead
  ].freeze
  RETRY_DELAYS = { "1m" => 60_000, "5m" => 300_000, "30m" => 1_800_000 }.freeze
  SHARD_COUNT = 4

  def self.declare!(broker = Hutch.broker)
    return unless broker&.channel

    new(broker.channel).declare!
  rescue StandardError => ex
    Rails.logger.warn("RabbitMQ topology declaration failed: #{ex.class}: #{ex.message}")
  end

  def self.publish_to_consistent_hash(topic:, payload:, subscription_id:, message_id:)
    return unless Hutch.broker&.channel && subscription_id.present?

    exchange = Hutch.broker.channel.exchange(HASH_EXCHANGE, type: "x-consistent-hash", durable: true)
    exchange.publish(payload.to_json,
                     routing_key:  subscription_id,
                     persistent:   true,
                     message_id:   message_id,
                     content_type: "application/json",
                     type:         topic)
  end

  def initialize(channel)
    @channel = channel
  end

  def declare!
    declare_exchanges
    declare_dead_letter_queues
    declare_retry_queues
    declare_consistent_hash_shards
  end

  private

  attr_reader :channel

  def declare_exchanges
    channel.exchange(MAIN_EXCHANGE, type: :topic, durable: true)
    channel.exchange(DEAD_LETTER_EXCHANGE, type: :topic, durable: true)
    channel.exchange(RETRY_EXCHANGE, type: :topic, durable: true)
    channel.exchange(HASH_EXCHANGE, type: "x-consistent-hash", durable: true)
  end

  def declare_dead_letter_queues
    exchange = channel.exchange(DEAD_LETTER_EXCHANGE, type: :topic, durable: true)

    DEAD_LETTER_ROUTING_KEYS.each do |routing_key|
      queue = channel.queue(routing_key, durable: true, arguments: dead_letter_queue_arguments)
      queue.bind(exchange, routing_key: routing_key)
    end
  end

  def declare_retry_queues
    exchange = channel.exchange(RETRY_EXCHANGE, type: :topic, durable: true)

    RETRY_DELAYS.each do |suffix, ttl|
      routing_key = "billing.retry.#{suffix}"
      queue = channel.queue(routing_key, durable: true, arguments: retry_queue_arguments(ttl))
      queue.bind(exchange, routing_key: routing_key)
    end
  end

  def declare_consistent_hash_shards
    exchange = channel.exchange(HASH_EXCHANGE, type: "x-consistent-hash", durable: true)

    SHARD_COUNT.times do |index|
      queue = channel.queue("billing.subscription_shard.#{index}", durable: true, arguments: shard_queue_arguments)
      queue.bind(exchange, routing_key: "1")
    end
  end

  def dead_letter_queue_arguments
    { "x-queue-type"             => "quorum",
      "x-single-active-consumer" => true }
  end

  def retry_queue_arguments(ttl)
    { "x-queue-type"             => "quorum",
      "x-single-active-consumer" => true,
      "x-message-ttl"            => ttl,
      "x-dead-letter-exchange"   => MAIN_EXCHANGE,
      "x-dead-letter-routing-key" => "billing.attempt.retry" }
  end

  def shard_queue_arguments
    { "x-queue-type"             => "quorum",
      "x-single-active-consumer" => true,
      "x-dead-letter-exchange"   => DEAD_LETTER_EXCHANGE }
  end
end
