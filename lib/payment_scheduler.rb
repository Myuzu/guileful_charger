# Naive PaymentScheduler implementation
#
# Value object for payment scheduler configuration
class PaymentSchedulerConfig < Dry::Struct
  attribute :max_retry_attempts,       Types::Integer.default(4)
  attribute :immediate_retry_strategy, Types::Array
  attribute :retry_partial_delay,      Types::Integer.default(1.week.freeze)
  attribute :base_delay,               Types::Integer # in seconds
  attribute :max_delay,                Types::Integer # in seconds
  attribute :jitter,                   Types::Bool.default(true)
end

class PaymentScheduler
  SQL_BATCH_SIZE = 50

  attr_reader :config

  def initialize(config)
    @config = config
  end

  def schedule_due_payments
    Subscription.due_for_payment
                .where(retry_count: 0)
                .lock("FOR UPDATE SKIP LOCKED")
                .find_each(batch_size: SQL_BATCH_SIZE) do |subscription|
                  schedule_initial_payment(subscription)
                end
  end

  def schedule_retries
    Subscription.requires_retry
                .where("retry_count < ?", config.max_retry_attempts)
                .lock("FOR UPDATE SKIP LOCKED")
                .find_each(batch_size: SQL_BATCH_SIZE) do |subscription|
                  schedule_retry_payment(subscription)
                end
  end

  private

  def schedule_initial_payment(subscription)
    # skip if we already have a pending PaymentAttempt
    return if subscription.payment_attempts.pending.exists?

    PaymentAttempt.transaction do
      attempt = create_payment_attempt(subscription)
      subscription.update!(
        next_payment_attempt_at: calculate_next_attempt_time(subscription),
      )
      Subscription::BillingService.call(payment_attempt: attempt)
    end
  end

  def create_payment_attempt(subscription)
    subscription.payment_attempts.create!(
      amount:       subscription.amount,
      status:       :pending,
      scheduled_at: Time.current
    )
  end

  def calculate_next_attempt_time(subscription)
    return subscription.current_period_end + 1.day if subscription.retry_count == 0

    delay = BASE_DELAY * (RETRY_MULTIPLIER ** (subscription.retry_count - 1))
    Time.current + [ delay, MAX_DELAY ].min
  end
end
