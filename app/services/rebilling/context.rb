# typed: strict

module Rebilling
  class Context
    extend Dry::Initializer
    extend T::Sig

    option :invoice_id
    option :invoice_status, Types::Coercible::Symbol
    option :invoice_total_cents, Types::NonNegativeInteger
    option :amount_paid_cents, Types::NonNegativeInteger
    option :subscription_status, Types::Coercible::Symbol
    option :attempts, Types::Array, default: proc { [] }
    option :payment_methods, Types::Array, default: proc { [] }
    option :customer_timezone, optional: true
    option :metadata, Types::Hash, default: proc { {} }

    sig { params(args: T.anything, kwargs: T.anything, block: T.nilable(Proc)).void }
    def initialize(*args, **kwargs, &block)
      super
      @attempts = T.let(attempts.freeze, T::Array[Attempt])
      @payment_methods = T.let(payment_methods.freeze, T::Array[PaymentMethodSnapshot])
      @metadata = T.let(metadata.freeze, T::Hash[Object, Object])

      freeze
    end

    sig { returns(Integer) }
    def amount_remaining_cents
      [ invoice_total_cents - amount_paid_cents, 0 ].max
    end

    sig { returns(T::Boolean) }
    def paid?
      invoice_status == :paid || amount_remaining_cents.zero?
    end

    sig { returns(T::Boolean) }
    def retryable_invoice?
      %i[open partially_paid].include?(invoice_status)
    end

    sig { returns(T::Boolean) }
    def active_subscription?
      subscription_status == :active
    end

    sig { returns(T::Boolean) }
    def in_flight_attempt?
      attempts.any?(&:in_flight?)
    end

    sig { returns(T.nilable(Attempt)) }
    def latest_terminal_attempt
      attempts.select(&:terminal?).max_by(&:attempt_number)
    end

    sig { returns(Integer) }
    def latest_attempt_number
      attempts.map(&:attempt_number).max || 0
    end

    sig { params(step_key: T.any(Symbol, String)).returns(T::Array[Attempt]) }
    def attempts_for_step(step_key)
      attempts.select { |attempt| attempt.retry_step_key == step_key.to_sym }
    end

    sig { returns(T::Hash[Symbol, Object]) }
    def to_h
      { invoice_id:              invoice_id,
        invoice_status:          invoice_status,
        invoice_total_cents:     invoice_total_cents,
        amount_paid_cents:       amount_paid_cents,
        amount_remaining_cents:  amount_remaining_cents,
        subscription_status:     subscription_status,
        customer_timezone:       customer_timezone,
        metadata:                metadata }
    end
  end
end
