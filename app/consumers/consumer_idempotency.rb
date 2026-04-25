require "digest"

module ConsumerIdempotency
  private

  def process_once(message)
    processed_message = claim_message(message)
    return log_duplicate_message(message) unless processed_message

    yield
  rescue StandardError
    processed_message&.destroy
    raise
  end

  def claim_message(message)
    ProcessedMessage.create!(consumer_name: self.class.name,
                             message_id:     idempotency_message_id(message))
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => ex
    raise unless duplicate_message_error?(ex)

    nil
  end

  def log_duplicate_message(message)
    logger.info "Ignoring duplicate message for #{self.class.name}: #{idempotency_message_id(message)}"
  end

  def message_value(message, key)
    message.body.fetch(key) { message.body.fetch(key.to_s) }
  end

  def stale_message?(message, subscription)
    message_version = message.body[:subscription_state_version] || message.body["subscription_state_version"]
    message_version.present? && message_version.to_i < subscription.state_version
  end

  def idempotency_message_id(message)
    explicit_message_id = message.message_id if message.respond_to?(:message_id)
    explicit_message_id.presence || Digest::SHA256.hexdigest("#{self.class.name}:#{message.body.to_json}")
  end

  def duplicate_message_error?(error)
    error.is_a?(ActiveRecord::RecordNotUnique) ||
      (error.respond_to?(:record) && error.record&.errors&.of_kind?(:message_id, :taken))
  end
end
