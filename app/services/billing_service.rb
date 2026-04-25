class BillingService < ApplicationService
  param :payment_attempt

  def call
    payload = { payment_attempt_id:         payment_attempt.id,
                subscription_id:            payment_attempt.subscription.id,
                subscription_state_version: payment_attempt.subscription.state_version }

    OutboxMessage.enqueue!(topic:             "billing.attempt.new",
                           payload:           payload,
                           aggregate:         payment_attempt.subscription,
                           aggregate_version: payment_attempt.subscription.state_version)
  end
end
