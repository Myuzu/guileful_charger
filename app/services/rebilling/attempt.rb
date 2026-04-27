module Rebilling
  class Attempt
    extend Dry::Initializer

    TERMINAL_STATUSES = %i[completed failed].freeze
    IN_FLIGHT_STATUSES = %i[pending scheduled processing].freeze

    option :id
    option :attempt_number, Types::Coercible::Integer
    option :status, Types::Coercible::Symbol
    option :amount_attempted_cents, Types::Coercible::Integer
    option :failure_reason, Types::Nil | Types::Coercible::Symbol, optional: true
    option :failure_category, Types::Nil | Types::Coercible::Symbol, optional: true
    option :retry_step_key, Types::Nil | Types::Coercible::Symbol, optional: true
    option :payment_method_id, optional: true
    option :strategy_version, optional: true
    option :created_at, optional: true
    option :completed_at, optional: true
    option :failed_at, optional: true

    def initialize(...)
      super
      freeze
    end

    def completed?
      status == :completed
    end

    def failed?
      status == :failed
    end

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def in_flight?
      IN_FLIGHT_STATUSES.include?(status)
    end

    def initial?
      retry_step_key.nil?
    end
  end
end
