module Rebilling
  class PaymentMethodSnapshot
    extend Dry::Initializer

    ACTIVE_STATUS = :active
    INELIGIBLE_STATUSES = %i[expired invalid requires_action disabled].freeze

    option :id
    option :status, Types::Coercible::Symbol, default: proc { :active }
    option :primary, Types::Bool, default: proc { false }
    option :kind, Types::Nil | Types::Coercible::Symbol, default: proc { :card }
    option :tokenization_kind, Types::Nil | Types::Coercible::Symbol, optional: true
    option :last_successful_at, optional: true
    option :last_failed_at, optional: true
    option :failure_category, Types::Nil | Types::Coercible::Symbol, optional: true

    def initialize(...)
      super
      freeze
    end

    def active?
      status == ACTIVE_STATUS
    end

    def hard_declined?
      failure_category == :hard_decline || INELIGIBLE_STATUSES.include?(status)
    end
  end
end
