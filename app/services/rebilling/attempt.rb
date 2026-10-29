# typed: strict

module Rebilling
  class Attempt
    extend Dry::Initializer
    extend T::Sig

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

    sig { params(args: T.anything, kwargs: T.anything, block: T.nilable(Proc)).void }
    def initialize(*args, **kwargs, &block)
      super
      freeze
    end

    sig { returns(T::Boolean) }
    def completed?
      status == :completed
    end

    sig { returns(T::Boolean) }
    def failed?
      status == :failed
    end

    sig { returns(T::Boolean) }
    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    sig { returns(T::Boolean) }
    def in_flight?
      IN_FLIGHT_STATUSES.include?(status)
    end

    sig { returns(T::Boolean) }
    def initial?
      retry_step_key.nil?
    end
  end
end
