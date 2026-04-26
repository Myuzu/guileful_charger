class ProcessPaymentService < ApplicationService
  SystemErrorResponse = Struct.new(:status, :transaction_id, :message, keyword_init: true) do
    def to_h
      { status:         status,
        transaction_id: transaction_id,
        message:        message }
    end
  end

  param :payment_attempt
  param :payment_gateway

  def call
    return payment_attempt_failure(:already_in_processing) if payment_attempt.processing?

    claim_result = claim_payment_attempt
    return claim_result if claim_result.failure?

    @response = process_payment

    ActiveRecord::Base.transaction(isolation: :serializable) do
      payment_attempt.reload
      handle_api_response
    end
  rescue StandardError => ex
    handle_exception(ex)
  end

  private

  attr_reader :response

  def claim_payment_attempt
    result = nil

    ActiveRecord::Base.transaction(isolation: :serializable) do
      payment_attempt.lock!
      payment_attempt.subscription.lock!

      result = validate_claimable_payment_attempt
      payment_attempt.start_processing! if result.success?
    end

    result
  end

  def validate_claimable_payment_attempt
    return payment_attempt_failure(:already_in_processing) if payment_attempt.processing?
    return payment_attempt_failure(:not_scheduled) unless payment_attempt.scheduled?
    return payment_attempt_failure(:subscription_not_active) unless payment_attempt.subscription.active?

    Success(payment_attempt)
  end

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
    when :system_error       then handle_api_system_error
    else
      raise StandardError.new("Unknown Payment Gateway API response status: #{response.status}")
    end
  end

  def handle_api_success
    payment_attempt.succeed!(response)
    Success(payment_attempt)
  end

  def handle_api_insufficient_funds
    payment_attempt.fail!(response, :insufficient_funds)
    payment_attempt_failure(:insufficient_funds)
  end

  def handle_api_failure
    payment_attempt.fail!(response, :gateway_error)
    payment_attempt_failure(:gateway_error)
  end

  def handle_api_system_error
    payment_attempt.fail!(response, :system_error)
    payment_attempt_failure(:system_error)
  end

  def handle_exception(ex)
    payment_attempt.fail!(response || system_error_response(ex), :system_error) if payment_attempt.processing?
    payment_attempt_failure(:system_error)
  end

  def payment_attempt_failure(code)
    service_failure(code,
                    payment_attempt:        payment_attempt,
                    payment_attempt_id:     payment_attempt.id,
                    payment_attempt_status: payment_attempt.status,
                    invoice_id:             payment_attempt.invoice_id)
  end

  def system_error_response(ex)
    SystemErrorResponse.new(status: :system_error,
                            transaction_id: nil,
                            message: ex.message)
  end
end
