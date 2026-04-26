class CancelSubscriptionService < ApplicationService
  param :subscription
  option :reason, optional: true

  input_schema do
    optional(:reason).maybe(:string)
  end

  def call
    Subscription.transaction do
      subscription.lock!

      return Success(subscription) if subscription.cancelled?

      subscription.cancel!(reason)
      enqueue_subscription_cancelled

      Success(subscription)
    end
  end

  private

  def enqueue_subscription_cancelled
    OutboxMessage.enqueue!(topic:             "subscription.cancelled",
                           payload:           lifecycle_payload,
                           aggregate:         subscription,
                           aggregate_version: subscription.state_version)
  end

  def lifecycle_payload
    subscription.lifecycle_payload(reason: reason)
  end
end
