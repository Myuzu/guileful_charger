# typed: strict

module Rebilling
  class DecisionOutcome
    extend Dry::Initializer
    extend T::Sig

    option :status, Types::DecisionStatus
    option :reason, Types::DecisionReason

    # Raw arguments pass through to dry-initializer; the RBI types .new's keywords.
    sig { params(args: T.anything, kwargs: T.anything, block: T.nilable(Proc)).void }
    def initialize(*args, **kwargs, &block)
      super
      freeze
    end
  end
end
