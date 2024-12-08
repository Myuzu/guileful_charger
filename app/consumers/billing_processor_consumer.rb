class BillingProcessorConsumer
  include Hutch::Consumer
  consume "billing.attempt.*"

  def process(message)
    logger.info "Message content: #{message.body.to_json}"

    payment_attempt = find_payment_attempt

    # we can inject different gateway implementation that supports #charge
    result = ProcessPaymentService.call(payment_attempt, PaymentGatewayApiMock.new)

    case result
    when Success
      publish_payment_success(result.value!)
    when Failure
      error_type, processed_attempt = result.failure
      case error_type
      when :insufficient_funds
        # schedule retry with lower amount
      when :gateway_error
        # log error and notify support
        # skip this branch for new
      when :system_error
        # log exception and retry later
      when :already_processed
        # handle duplicate processing attempt
        # skip this branch for now
      end
    end
  end

  private

  def find_payment_attempt
    attempt_id = message.body.fetch(:payment_attempt_id)
    PaymentAttempt.find(attempt_id)
  end

  def publish_payment_success(processed_attempt)
    payload = { payment_attempt_id:  processed_attempt.id }
    Hutch.publish("billing.payment.full.success", payload)
  end

  def publish_payment_retry(processed_attempt)
  end
end
