# typed: true

module Rebilling
  # notification_intent is reserved for the Tier 2 notification ladder. The
  # rules-only Tier 1 strategy intentionally emits :none for every decision.
  Decision = Data.define(:status, :reason, :plan, :diagnostics, :trace, :notification_intent) do
    extend T::Sig

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
