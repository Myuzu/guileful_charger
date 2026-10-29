# typed: strict

module Rebilling
  class ScoringPolicy
    extend T::Sig

    # Reserved hook: the rules-only planner does not consult these nil scores.
    sig { params(_context: T.anything, candidate_steps: T::Array[RetryStep]).returns(T::Hash[Symbol, NilClass]) }
    def score(_context, candidate_steps)
      candidate_steps.to_h { |step| [ step.key, nil ] }
    end
  end
end
