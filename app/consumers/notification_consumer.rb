# routing keys to consume
# * billing.payment.full.success
# * billing.payment.partial.success
# * billing.payment.failed
# * billing.attempt.new
# * billing.attempt.retry
# * billing.retry.exhausted

class NotificationConsumer
  include Hutch::Consumer
  include ConsumerIdempotency

  consume "billing.*"
  BillingConsumerQueueOptions.apply(self, dead_letter_routing_key: "billing.notification.dead")

  def process(message)
    process_once(message) do
      logger.info "Message content #{message.body.to_json}"
    end
  end
end
