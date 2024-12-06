class InvoiceConsumer
  include Hutch::Consumer
  consume "invoice.created"

  def process(message)
    logger.info "Message content: #{message.body.to_json}"

    invoice = Invoice.find(message.body.fetch(:invoice_id))

    return unless invoice.draft?

    invoice.open_new!
    payment_attempt = invoice.payment_attempts.first

    Hutch.publish("billing.attempt.new", { payment_attempt_id: payment_attempt.id })
  end
end
