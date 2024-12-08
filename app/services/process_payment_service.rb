class ProcessPaymentService < ApplicationService
  include Dry::Monads[:result]

  param :payment_attempt
  param :payment_gateway

  def call
    # FIXME: probably skip on all other statuses except `scheduled`
    return Failure[:already_in_processing, payment_attempt] if payment_attempt.processing?

    ActiveRecord::Base.transaction(isolation: :serializable) do
      payment_attempt.start_processing!
      @response = process_payment
      handle_api_response
    end
  rescue StandardError => ex
    handle_exception(ex)
  end

  private

  attr_reader :response

  def process_payment
    payment_gateway.charge(
      amount:          payment_attempt.amount_attempted_cents,
      subscription_id: payment_attempt.invoice.subscription_id
    )
  end

  def handle_api_response
    case response.status
    when :success            then handle_api_success
    when :insufficient_funds then handle_api_insufficient_funds
    when :failed             then handle_api_failure
    else
      raise StandardError.new("Unknow Payment Gateway API response status: #{response.status}")
    end
  end

  def handle_api_success
    payment_attempt.succeed!(response)
    Success(payment_attempt)
  end

  def handle_api_insufficient_funds
    payment_attempt.fail!(response, :insufficient_funds)
    Failure[:insufficient_funds, payment_attempt]
  end

  def handle_api_failure
    payment_attempt.fail!(response, :gateway_error)
    Failure[:gateway_error, payment_attempt]
  end

  def handle_exception(ex)
    payment_attempt.fail!(response, :system_error)
    Failure[:system_error, payment_attempt]
  end
end
