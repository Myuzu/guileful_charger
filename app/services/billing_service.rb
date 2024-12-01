class BillingService < ApplicationService
  param :payment_attempt

  def call
  rescue Hutch::ConnectionError => ex
    logger.error("Hutch::ConnectionError: #{ex}")
  end
end
