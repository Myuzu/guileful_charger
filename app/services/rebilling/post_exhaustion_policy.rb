# typed: strict

module Rebilling
  class PostExhaustionPolicy
    extend T::Sig

    DEFAULT_ACTION = :pause_subscription

    sig { params(_invoice: T.anything, _exhaustion_reason: T.anything).returns(Symbol) }
    def handle(_invoice, _exhaustion_reason)
      DEFAULT_ACTION
    end
  end
end
