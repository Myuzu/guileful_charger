module Rebilling
  class DecisionOutcome
    extend Dry::Initializer

    option :status, Types::DecisionStatus
    option :reason, Types::DecisionReason

    def initialize(...)
      super
      freeze
    end
  end
end
