module Rebilling
  module Types
    include Dry.Types()

    VALID_BASES = %i[invoice_total remaining_balance].freeze
    VALID_TRANSITIONS = %i[repeat next stop].freeze
    VALID_PAYMENT_METHOD_ORDERS = %i[primary_then_recent_success].freeze
    # Some symbols intentionally appear in both lists when the status and the
    # most precise reason are the same, e.g. :in_flight_attempt_exists and
    # :no_eligible_payment_method.
    VALID_DECISION_STATUSES = %i[
      exhausted
      in_flight_attempt_exists
      invoice_paid
      no_eligible_payment_method
      not_retryable
      scheduled
      subscription_inactive
    ].freeze
    VALID_DECISION_REASONS = %i[
      completed_initial_attempt_not_reconciled
      initial_attempt_failed
      invoice_already_paid
      invoice_not_retryable
      in_flight_attempt_exists
      last_step_failed
      last_step_succeeded
      max_attempts_reached
      no_eligible_payment_method
      no_next_step
      no_terminal_attempt
      non_retryable_failure_reason
      step_chain_stopped
      subscription_not_active
      unknown_step_key
    ].freeze

    Basis = Nominal::Any.constructor do |value|
      symbol = value.to_sym
      raise ArgumentError, "basis must be one of: #{VALID_BASES.join(', ')}" unless VALID_BASES.include?(symbol)

      symbol
    end

    Transition = Nominal::Any.constructor do |value|
      symbol = value.to_sym
      raise ArgumentError, "transition must be one of: #{VALID_TRANSITIONS.join(', ')}" unless VALID_TRANSITIONS.include?(symbol)

      symbol
    end

    PaymentMethodOrder = Nominal::Any.constructor do |value|
      symbol = value.to_sym
      unless VALID_PAYMENT_METHOD_ORDERS.include?(symbol)
        raise ArgumentError, "payment method order must be one of: #{VALID_PAYMENT_METHOD_ORDERS.join(', ')}"
      end

      symbol
    end

    DecisionStatus = Nominal::Any.constructor do |value|
      symbol = value.to_sym
      raise ArgumentError, "decision status must be one of: #{VALID_DECISION_STATUSES.join(', ')}" unless VALID_DECISION_STATUSES.include?(symbol)

      symbol
    end

    DecisionReason = Nominal::Any.constructor do |value|
      symbol = value.to_sym
      raise ArgumentError, "decision reason must be one of: #{VALID_DECISION_REASONS.join(', ')}" unless VALID_DECISION_REASONS.include?(symbol)

      symbol
    end

    Percentage = Nominal::Any.constructor do |value|
      number = begin
        Float(value)
      rescue TypeError, ArgumentError
        raise ArgumentError, "percentage must be numeric"
      end

      raise ArgumentError, "percentage must be greater than 0" unless number.positive?
      raise ArgumentError, "percentage must be less than or equal to 100" if number > 100

      number % 1 == 0 ? number.to_i : number
    end

    NonNegativeInteger = Nominal::Any.constructor do |value|
      integer = Integer(value)
      raise ArgumentError, "integer must be greater than or equal to 0" if integer.negative?

      integer
    rescue TypeError, ArgumentError
      raise ArgumentError, "integer must be greater than or equal to 0"
    end

    Seconds = Nominal::Any.constructor do |value|
      seconds = value.to_i
      raise ArgumentError, "seconds must be greater than or equal to 0" if seconds.negative?

      seconds
    end

    JitterRange = Nominal::Any.constructor do |value|
      range = value || (0..0)
      raise ArgumentError, "jitter must be a Range" unless range.is_a?(::Range)
      raise ArgumentError, "jitter must use an inclusive Range" if range.exclude_end?

      start_seconds = Seconds[range.begin]
      end_seconds = Seconds[range.end]
      raise ArgumentError, "jitter end must be greater than or equal to jitter begin" if end_seconds < start_seconds

      start_seconds..end_seconds
    end
  end
end
