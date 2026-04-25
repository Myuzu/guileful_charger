module BillingConsumerQueueOptions
  DEAD_LETTER_EXCHANGE = "billing.events.dlx".freeze
  DELIVERY_LIMIT = 5

  def self.apply(consumer, dead_letter_routing_key:)
    consumer.quorum_queue
    consumer.arguments("x-dead-letter-exchange"     => DEAD_LETTER_EXCHANGE,
                       "x-dead-letter-routing-key" => dead_letter_routing_key,
                       "x-delivery-limit"          => DELIVERY_LIMIT,
                       "x-single-active-consumer"  => true)
  end
end
