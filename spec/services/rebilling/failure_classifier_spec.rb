# rubocop:disable RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe Rebilling::FailureClassifier do
  def attempt(reason: nil, category: nil)
    Rebilling::Attempt.new(id:                     "pa_1",
                           attempt_number:         1,
                           status:                 :failed,
                           amount_attempted_cents: 100,
                           failure_reason:         reason,
                           failure_category:       category)
  end

  it "preserves populated failure categories" do
    classification = described_class.new.classify_attempt(attempt(category: :hard_decline))

    aggregate_failures do
      expect(classification.category).to eq(:hard_decline)
      expect(classification.retryable).to be(false)
    end
  end

  it "treats populated soft-decline categories as retryable" do
    classification = described_class.new.classify_attempt(attempt(category: :soft_decline))

    aggregate_failures do
      expect(classification.category).to eq(:soft_decline)
      expect(classification.retryable).to be(true)
    end
  end

  it "classifies insufficient funds as a retryable soft decline" do
    classification = described_class.new.classify_attempt(attempt(reason: :insufficient_funds))

    aggregate_failures do
      expect(classification.category).to eq(:soft_decline)
      expect(classification.retryable).to be(true)
    end
  end

  it "classifies stolen cards as hard declines" do
    classification = described_class.new.classify_attempt(attempt(reason: :stolen_card))

    aggregate_failures do
      expect(classification.category).to eq(:hard_decline)
      expect(classification.retryable).to be(false)
    end
  end

  it "classifies authentication failures as customer action required" do
    classification = described_class.new.classify_attempt(attempt(reason: :authentication_required))

    aggregate_failures do
      expect(classification.category).to eq(:customer_action_required)
      expect(classification.customer_action_required).to be(true)
    end
  end

  it "classifies system errors as technical failures" do
    classification = described_class.new.classify_attempt(attempt(reason: :system_error))

    aggregate_failures do
      expect(classification.category).to eq(:technical_failure)
      expect(classification.retryable).to be(false)
    end
  end

  it "classifies unmapped and empty reasons as unknown" do
    classifier = described_class.new

    aggregate_failures do
      expect(classifier.classify_attempt(attempt(reason: :custom_gateway_error)).category).to eq(:unknown)
      expect(classifier.classify_attempt(attempt).category).to eq(:unknown)
    end
  end

  it "prefers the populated category over a conflicting failure reason" do
    classification = described_class.new.classify_attempt(attempt(reason: :insufficient_funds, category: :hard_decline))

    aggregate_failures do
      expect(classification.category).to eq(:hard_decline)
      expect(classification.retryable).to be(false)
    end
  end
end
