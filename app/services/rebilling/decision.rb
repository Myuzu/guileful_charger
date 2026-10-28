# typed: true

module Rebilling
  # notification_intent is reserved for the Tier 2 notification ladder. The
  # rules-only Tier 1 strategy intentionally emits :none for every decision.
  Decision = Data.define(:status, :reason, :plan, :diagnostics, :trace, :notification_intent)

  class Decision
    extend T::Sig

    # This adoption boundary types the factory's return only. Inputs remain
    # untyped until the dry-initializer DTO interfaces are modeled explicitly.
    sig do
      params(outcome: T.untyped, plan: T.untyped, diagnostics: T.untyped,
        trace: T.untyped, notification_intent: T.untyped).returns(Decision)
    end
    def self.from_outcome(outcome, plan: nil, diagnostics: {}, trace: [], notification_intent: :none)
      new(status:              outcome.status,
          reason:              outcome.reason,
          plan:                plan,
          diagnostics:         diagnostics,
          trace:               trace,
          notification_intent: notification_intent)
    end

    def scheduled?
      status == :scheduled
    end

    def exhausted?
      status == :exhausted
    end
  end
end
