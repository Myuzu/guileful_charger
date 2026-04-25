class ResumeSubscriptionService < ApplicationService
  include Dry::Monads[:result]

  param :subscription
  option :reason, optional: true

  def call
    Subscription.transaction do
      subscription.lock!

      return Success(subscription) if subscription.active?
      return Failure[:already_cancelled, subscription] if subscription.cancelled?

      subscription.resume!(reason)
      enqueue_subscription_resumed
      enqueue_scheduled_payment_attempts

      Success(subscription)
    end
  end

  private

  def enqueue_subscription_resumed
    OutboxMessage.enqueue!(topic:             "subscription.resumed",
                           payload:           lifecycle_payload,
                           aggregate:         subscription,
                           aggregate_version: subscription.state_version)
  end

  def lifecycle_payload
    subscription.lifecycle_payload(reason: reason)
  end

  def enqueue_scheduled_payment_attempts
    PaymentAttempt.scheduled
                  .joins(:invoice)
                  .where(invoices: { subscription_id: subscription.id })
                  .find_each do |payment_attempt|
                    OutboxMessage.enqueue!(topic:             "billing.attempt.new",
                                           payload:           billing_attempt_payload(payment_attempt),
                                           aggregate:         subscription,
                                           aggregate_version: subscription.state_version)
                  end
  end

  def billing_attempt_payload(payment_attempt)
    { payment_attempt_id:         payment_attempt.id,
      subscription_id:            subscription.id,
      subscription_state_version: subscription.state_version }
  end
end
