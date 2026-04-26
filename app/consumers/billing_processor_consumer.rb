class BillingProcessorConsumer
  PaymentProcessingRetryableError = Class.new(StandardError)

  include ActiveConsumer
  include Dry::Monads[:result]

  consume "billing.attempt.*"

  consumer_options do
    quorum_queue
    dead_letter routing_key: "billing.attempt.dead"
    delivery_limit
    single_active_consumer
  end

  message_schema do
    required(:payment_attempt_id).filled(:string)
    optional(:subscription_id).filled(:string)
    optional(:subscription_state_version).maybe(:integer)
  end

  private

  def process_message(message, payload)
    logger.info "Message content: #{message.body.to_json}"

    payment_attempt = find_payment_attempt(payload)
    skipped_reason = unprocessable_reason(payment_attempt, payload)

    if skipped_reason
      publish_payment_skipped(payment_attempt, skipped_reason)
      return
    end

    # we can inject different gateway implementation that supports #charge
    result = ProcessPaymentService.call(payment_attempt, PaymentGatewayApiMock.new)

    case result
    when Success
      publish_payment_success(result.value!)
    when Failure
      error_type, processed_attempt = result.failure
      handle_payment_failure(error_type, processed_attempt)
    end
  end

  def find_payment_attempt(payload)
    PaymentAttempt.find(payload.fetch(:payment_attempt_id))
  end

  def unprocessable_reason(payment_attempt, payload)
    payment_attempt.reload
    subscription = payment_attempt.subscription

    return :not_scheduled unless payment_attempt.scheduled?
    return :subscription_not_active unless subscription.active?
    :stale_message if stale_payload?(payload, subscription)
  end

  def stale_payload?(payload, subscription)
    payload[:subscription_state_version].present? && payload[:subscription_state_version] < subscription.state_version
  end

  def handle_payment_failure(error_type, processed_attempt)
    case error_type
    when :insufficient_funds, :gateway_error
      logger.warn("Payment attempt #{processed_attempt.id} failed: #{error_type}")
      publish_payment_failed(processed_attempt, error_type)
    when :system_error
      logger.error("Payment attempt #{processed_attempt.id} failed with retryable system error")
      publish_payment_failed(processed_attempt, error_type)
      raise PaymentProcessingRetryableError, "Payment attempt #{processed_attempt.id} failed with system_error"
    when :already_processed, :already_in_processing, :not_scheduled, :subscription_not_active
      logger.info("Payment attempt #{processed_attempt.id} skipped: #{error_type}")
      publish_payment_skipped(processed_attempt, error_type)
    else
      logger.error("Payment attempt #{processed_attempt.id} returned unknown failure: #{error_type}")
      publish_payment_failed(processed_attempt, error_type)
    end
  end

  def publish_payment_success(processed_attempt)
    enqueue_payment_event("billing.payment.full.success", processed_attempt)
  end

  def publish_payment_failed(processed_attempt, failure_reason)
    enqueue_payment_event("billing.payment.failed", processed_attempt, failure_reason: failure_reason)
  end

  def publish_payment_skipped(processed_attempt, skipped_reason)
    enqueue_payment_event("billing.payment.skipped", processed_attempt, skipped_reason: skipped_reason)
  end

  def enqueue_payment_event(topic, processed_attempt, extra_payload = {})
    subscription = processed_attempt.subscription
    payload = { payment_attempt_id:         processed_attempt.id,
                subscription_id:            subscription.id,
                subscription_state_version: subscription.state_version }.merge(extra_payload)

    OutboxMessage.enqueue!(topic:             topic,
                           payload:           payload,
                           aggregate:         subscription,
                           aggregate_version: subscription.state_version)
  end
end
