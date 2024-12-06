class BillingService < ApplicationService
  param :payment_attempt

  def call
    payload = { subject:         "payment",
                retry_count:     0,
                payment_attempt: payment_attempt.created_at,
                subscription:    subscription.id }

    Hutch.publish("billing.attempt.new", payload)
  rescue Hutch::ConnectionError => ex
    logger.error("Hutch::ConnectionError: #{ex}")
  end
end
