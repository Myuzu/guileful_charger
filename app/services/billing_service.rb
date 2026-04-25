class BillingService < ApplicationService
  param :payment_attempt

  def call
    payload = { payment_attempt_id: payment_attempt.id,
                subscription_id:    payment_attempt.subscription.id }

    Hutch.publish("billing.attempt.new", payload)
  rescue Hutch::ConnectionError => ex
    logger.error("Hutch::ConnectionError: #{ex}")
  end
end
