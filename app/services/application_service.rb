require "dry-validation"

class ApplicationService
  extend Dry::Initializer
  extend Dry::Monads[:result]
  include Dry::Monads[:result]

  def self.call(*args, **kwargs, &block)
    input_result = validate_input(kwargs)
    return input_result if input_result.failure?

    new(*args, **input_result.value!, &block).call
  end

  def self.input_schema(&block)
    @input_schema_block = block
    @input_contract = nil
  end

  def self.input_contract
    @input_contract ||= build_input_contract
  end

  def self.validate_input(input)
    return Success(input) unless @input_schema_block

    result = input_contract.call(input)
    return Success(input.merge(result.to_h)) if result.success?

    Failure[:invalid_input, { errors: result.errors.to_h }]
  end

  def self.build_input_contract
    schema_block = @input_schema_block

    Class.new(Dry::Validation::Contract) do
      # Use a strict schema for in-process service commands: callers should pass
      # correctly typed Ruby values, not HTTP/message-style values that need
      # coercion. `result.to_h` includes only declared keys, so validate_input
      # merges validated declared values back into the original keyword hash to
      # preserve undeclared Dry::Initializer options instead of silently dropping
      # them.
      schema(&schema_block)
    end.new
  end
  private_class_method :build_input_contract

  private

  def failure_result(code, **metadata)
    Failure[code, metadata]
  end

  def subscription_metadata(subscription)
    { subscription_id: subscription.id,
      status:          subscription.status,
      state_version:   subscription.state_version }
  end

  def subscription_failure(code, subscription, **metadata)
    failure_result(code, **metadata.merge(subscription_metadata(subscription)))
  end

  def payment_attempt_metadata(payment_attempt)
    { payment_attempt_id:     payment_attempt.id,
      payment_attempt_status: payment_attempt.status,
      invoice_id:             payment_attempt.invoice_id }
  end

  def payment_attempt_failure(code, payment_attempt, **metadata)
    structured_metadata = { payment_attempt: payment_attempt }.merge(payment_attempt_metadata(payment_attempt))

    failure_result(code, **metadata.merge(structured_metadata))
  end
end
