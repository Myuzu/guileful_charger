# typed: strict

module Rebilling
  module DecisionRecorderContract
    extend T::Sig
    extend T::Helpers
    interface!

    # The planner ignores the recorder's return value.
    sig { abstract.params(context: Context, decision: Decision).returns(T.anything) }
    def record(context, decision); end
  end
end
