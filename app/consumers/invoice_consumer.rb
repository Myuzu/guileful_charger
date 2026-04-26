class InvoiceConsumer
  include ActiveConsumer

  consume "invoice.created"

  consumer_options do
    quorum_queue
    dead_letter routing_key: "invoice.created.dead"
    delivery_limit
    single_active_consumer
  end

  message_schema do
    required(:invoice_id).filled(:string)
    optional(:subscription_state_version).maybe(:integer)
  end

  private

  def process_message(message, payload)
    logger.info "Message content: #{message.body.to_json}"

    Invoice.transaction do
      invoice = Invoice.lock.find(payload.fetch(:invoice_id))
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
