module Rebilling
  class DecisionRecorder
    def record(_context, _decision)
      nil
    end

    def record_shadows(_context, _primary_decision, _shadow_decisions)
      nil
    end
  end
end
