class BillingConsumer
  include Hutch::Consumer
  consume "payment_attempt.perform"

  def process(message)
    binding.irb
    logger.info "Message content #{message.body.to_json}"
  end

  private

  def find_payment_attempt
    attempt_id = message.body.fetch(:payment_attempt_id)
    PaymentAttempt.find(attempt_id)
  end
end
