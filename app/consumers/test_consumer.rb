class TestConsumer
  include Hutch::Consumer
  consume "payment.failed"

  def process(message)
    logger.info "Marking payment #{message.message_id} as failed"
    logger.info "Message content #{message.body.to_json}"
  end
end
