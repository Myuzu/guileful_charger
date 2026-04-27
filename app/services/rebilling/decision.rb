module Rebilling
  # notification_intent is reserved for the Tier 2 notification ladder. The
  # rules-only Tier 1 strategy intentionally emits :none for every decision.
  class Decision < Data.define(:status, :reason, :plan, :diagnostics, :trace, :notification_intent)
    def self.from_outcome(outcome, plan: nil, diagnostics: {}, trace: [], notification_intent: :none)
      new(status:              outcome.status,
          reason:              outcome.reason,
          plan:                plan,
          diagnostics:         immutable_copy(diagnostics),
          trace:               immutable_copy(trace),
          notification_intent: notification_intent)
    end

    def self.immutable_copy(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child_value), copy|
          copy[immutable_copy(key)] = immutable_copy(child_value)
        end.freeze
      when Array
        value.map { |child_value| immutable_copy(child_value) }.freeze
      when NilClass, TrueClass, FalseClass, Numeric, Symbol
        value
      else
        value.dup.freeze
      end
    rescue TypeError
      value
    end

    def scheduled?
      status == :scheduled
    end

    def exhausted?
      status == :exhausted
    end
  end
end
