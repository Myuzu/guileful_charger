module Rebilling
  class Context
    extend Dry::Initializer

    option :invoice_id
    option :invoice_status, Types::Coercible::Symbol
    option :invoice_total_cents, Types::NonNegativeInteger
    option :amount_paid_cents, Types::NonNegativeInteger
    option :subscription_status, Types::Coercible::Symbol
    option :attempts, Types::Array, default: proc { [] }
    option :payment_methods, Types::Array, default: proc { [] }
    option :customer_timezone, optional: true
    option :metadata, Types::Hash, default: proc { {} }

    def initialize(...)
      super
      @attempts = attempts.freeze
      @payment_methods = payment_methods.freeze
      @metadata = metadata.freeze

      freeze
    end

    def amount_remaining_cents
      [ invoice_total_cents - amount_paid_cents, 0 ].max
    end

    def paid?
      invoice_status == :paid || amount_remaining_cents.zero?
    end

    def retryable_invoice?
      %i[open partially_paid].include?(invoice_status)
    end

    def active_subscription?
      subscription_status == :active
    end

    def in_flight_attempt?
      attempts.any?(&:in_flight?)
    end

    def latest_terminal_attempt
      attempts.select(&:terminal?).max_by(&:attempt_number)
    end

    def latest_attempt_number
      attempts.map(&:attempt_number).max || 0
    end

    def attempts_for_step(step_key)
      attempts.select { |attempt| attempt.retry_step_key == step_key.to_sym }
    end

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
