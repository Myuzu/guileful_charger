# Naive PaymentScheduler implementation
#
# Value object for payment scheduler configuration
class PaymentSchedulerConfig < Dry::Struct
  attribute :max_retry_attempts, Types::Integer.default(4)
  attribute :batch_size,         Types::Integer.default(25)
  attribute :jitter,             Types::Bool.default(true)
end

class PaymentScheduler
  attr_reader :config

  def initialize(config)
    @config = config
  end

  def run!
    Subscription.due_for_payment
                .lock("FOR UPDATE SKIP LOCKED")
                .find_each(batch_size: 25) do |subscription|
                  subscription.issue_new_invoice!
                  publish_invoice_created(subscription)
                end
  end

  private

  def publish_invoice_created(subscription)
    payload = { invoice_id: subscription.latest_invoice.id }
    Hutch.publish("invoice.created", payload)
  end
end
