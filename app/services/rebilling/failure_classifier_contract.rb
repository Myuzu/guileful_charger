# typed: strict

module Rebilling
  module FailureClassifierContract
    extend T::Sig
    extend T::Helpers

    interface!

    sig { abstract.params(attempt: Attempt).returns(FailureClassification) }
    def classify_attempt(attempt); end
  end
end
