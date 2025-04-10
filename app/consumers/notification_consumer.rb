# routing keys to consume
# * billing.payment.full.success
# * billing.payment.partial.success
# * billing.payment.failed
# * billing.attempt.new
# * billing.attempt.retry
# * billing.retry.exhausted

class NotificationConsumer
  include Hutch::Consumer
  consume "billing.*"

  def process(message)
    logger.info "Message content #{message.body.to_json}"
  end

  private

  def find_payment_attempt
    attempt_id = message.body.fetch(:payment_attempt_id)
    PaymentAttempt.find(attempt_id)
  end
end
