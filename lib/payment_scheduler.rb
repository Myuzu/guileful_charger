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

  def run!
    Subscription.with_latest_invoice(:draft)
                .lock("FOR UPDATE SKIP LOCKED")
                .find_each(batch_size: 25) do |subscription|
                  schedule_initial_payment(subscription)
                end
  end

  private

  def schedule_initial_payment(subscription)
    invoice = subscription.latest_invoice
    Invoice.transaction(isolation: :serializable) do
      attempt = invoice.create_new_payment_attempt
      Subscription::BillingService.call(payment_attempt: attempt)
    end
  end
end
