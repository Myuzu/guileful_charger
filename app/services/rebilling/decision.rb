# typed: true

module Rebilling
  # notification_intent is reserved for the Tier 2 notification ladder. The
  # rules-only Tier 1 strategy intentionally emits :none for every decision.
  Decision = Data.define(:status, :reason, :plan, :diagnostics, :trace, :notification_intent)

  class Decision
    extend T::Sig

    sig do
      params(outcome: DecisionOutcome, plan: T.nilable(Plan), diagnostics: T::Hash[Symbol, Object],
        trace: T::Array[T::Hash[Symbol, Object]], notification_intent: Symbol).returns(Decision)
    end
    def self.from_outcome(outcome, plan: nil, diagnostics: {}, trace: [], notification_intent: :none)
      new(status:              outcome.status,
          reason:              outcome.reason,
          plan:                plan,
          diagnostics:         diagnostics,
          trace:               trace,
          notification_intent: notification_intent)
    end

    sig { returns(T::Boolean) }
    def scheduled?
      status == :scheduled
    end

    sig { returns(T::Boolean) }
    def exhausted?
      status == :exhausted
    end
  end
end
