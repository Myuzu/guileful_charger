class InvoiceConsumer
  include Hutch::Consumer
  include ConsumerIdempotency

  consume "invoice.created"
  BillingConsumerQueueOptions.apply(self, dead_letter_routing_key: "invoice.created.dead")

  def process(message)
    process_once(message) { process_message(message) }
  end

  private

  def process_message(message)
    logger.info "Message content: #{message.body.to_json}"

    Invoice.transaction do
      invoice = Invoice.lock.find(message_value(message, :invoice_id))
      subscription = invoice.subscription
      subscription.lock!

      next unless invoice.draft?
      next unless subscription.active?
      next if stale_message?(message, subscription)

      invoice.open_new!
      payment_attempt = invoice.payment_attempts.first
      raise "Invoice #{invoice.id} did not create a payment attempt" unless payment_attempt

      payment_attempt.schedule! if payment_attempt.pending?
      enqueue_billing_attempt(payment_attempt, subscription)
    end
  rescue ActiveRecord::RecordNotFound
    logger.info "Ignoring stale invoice.created message: #{message.body.to_json}"
  end

  def enqueue_billing_attempt(payment_attempt, subscription)
    OutboxMessage.enqueue!(topic:             "billing.attempt.new",
                           payload:           billing_attempt_payload(payment_attempt, subscription),
                           aggregate:         subscription,
                           aggregate_version: subscription.state_version)
  end

  def billing_attempt_payload(payment_attempt, subscription)
    { payment_attempt_id:          payment_attempt.id,
      subscription_id:             subscription.id,
      subscription_state_version:  subscription.state_version }
  end
end
