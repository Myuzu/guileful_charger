# routing keys to consume
# * billing.payment.partial.success
# * billing.payment.failed

class RetryManagerConsumer
  include Hutch::Consumer
  include ConsumerIdempotency

  consume "billing.payment.*"
  BillingConsumerQueueOptions.apply(self, dead_letter_routing_key: "billing.retry.dead")

  def process(message)
    process_once(message) do
      logger.info "Message content #{message.body.to_json}"
    end
  end
end
