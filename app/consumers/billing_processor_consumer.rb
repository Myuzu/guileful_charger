class BillingProcessorConsumer
  include Hutch::Consumer
  consume "billing.attempt.*"

  def process(message)
    logger.info "Message content: #{message.body.to_json}"

    payment_attempt = find_payment_attempt
    result = ProcessPaymentService.call(payment_attempt, PaymentGatewayApiMock.new)

    case result
    when Success
      publish_payment_success(result.value!)
    when Failure
      error_type, processed_attempt = result.failure
      case error_type
      when :insufficient_funds
        # Schedule retry with lower amount
      when :gateway_error
        # Log error and notify support
      when :system_error
        # Log exception and retry later
      when :already_processed
        # Handle duplicate processing attempt
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
end
