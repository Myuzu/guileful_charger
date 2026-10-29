# typed: strict

module Rebilling
  class DecisionRecorder
    extend T::Sig
    include DecisionRecorderContract

    sig { override.params(_context: T.anything, _decision: T.anything).returns(NilClass) }
    def record(_context, _decision)
      nil
    end

    sig { params(_context: T.anything, _primary_decision: T.anything, _shadow_decisions: T.anything).returns(NilClass) }
    def record_shadows(_context, _primary_decision, _shadow_decisions)
      nil
    end
  end
end
