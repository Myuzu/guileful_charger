# routing keys to consume
# * billing.payment.full.success
# * billing.payment.partial.success
# * billing.payment.failed
# * billing.attempt.new
# * billing.attempt.retry
# * billing.retry.exhausted

class NotificationConsumer
  include ActiveConsumer

  consume "billing.*"

  consumer_options do
    quorum_queue
    dead_letter routing_key: "billing.notification.dead"
    delivery_limit
    single_active_consumer
  end

  message_schema do
    optional(:payment_attempt_id).filled(:string)
    optional(:subscription_id).filled(:string)
    optional(:subscription_state_version).maybe(:integer)
    optional(:failure_reason).filled(:string)
    optional(:skipped_reason).filled(:string)
  end

  message_rule do
    next if values[:payment_attempt_id] || values[:subscription_id]

    base.failure("must include payment_attempt_id or subscription_id")
  end

  private

  def process_message(_message, payload)
    logger.info "Message content #{payload.to_json}"
  end
end
