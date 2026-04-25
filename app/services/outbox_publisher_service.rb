class OutboxPublisherService < ApplicationService
  DEFAULT_BATCH_SIZE = 100
  DEFAULT_LOCK_TIMEOUT = 15.minutes

  option :batch_size, default: proc { DEFAULT_BATCH_SIZE }
  option :lock_timeout, default: proc { DEFAULT_LOCK_TIMEOUT }

  def call
    claim_batch.each { |message| publish_message(message) }
  end

  private

  def claim_batch
    claimed_messages = []

    OutboxMessage.transaction do
      claimed_messages = OutboxMessage.claimable(Time.current - lock_timeout)
                                      .order(:created_at)
                                      .lock("FOR UPDATE SKIP LOCKED")
                                      .limit(batch_size)
                                      .to_a
      OutboxMessage.where(id: claimed_messages.map(&:id)).update_all(locked_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    claimed_messages
  end

  def publish_message(message)
    Hutch.publish(message.topic, message.payload, { message_id: message.id })
    mirror_to_consistent_hash_exchange(message)
    mark_published(message)
  rescue StandardError => ex
    mark_failed(message, ex)
  end

  def mark_published(message)
    OutboxMessage.where(id: message.id).update_all(published_at: Time.current,
                                                   locked_at:    nil,
                                                   attempts:     message.attempts + 1,
                                                   last_error:   nil,
                                                   updated_at:   Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def mark_failed(message, error)
    OutboxMessage.where(id: message.id).update_all(locked_at:  nil,
                                                   attempts:   message.attempts + 1,
                                                   last_error: error.message,
                                                   updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def mirror_to_consistent_hash_exchange(message)
    RabbitMqTopology.publish_to_consistent_hash(topic:           message.topic,
                                                payload:          message.payload,
                                                subscription_id:  message.payload["subscription_id"],
                                                message_id:       message.id)
  rescue StandardError => ex
    Rails.logger.warn("Consistent-hash mirror publish failed for outbox #{message.id}: #{ex.class}: #{ex.message}")
  end
end
