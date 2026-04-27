module Rebilling
  class ScoringPolicy
    def score(_context, candidate_steps)
      candidate_steps.to_h { |step| [ step.key, nil ] }
    end
  end
end
