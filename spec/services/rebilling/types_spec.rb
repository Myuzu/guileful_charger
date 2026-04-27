# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe Rebilling::Types do
  it "coerces and validates percentages" do
    aggregate_failures do
      expect(described_class::Percentage["12.5"]).to eq(12.5)
      expect(described_class::Percentage["25"]).to eq(25)
      expect { described_class::Percentage[0] }.to raise_error(Dry::Types::CoercionError, /percentage must be greater than 0/)
      expect { described_class::Percentage[101] }.to raise_error(Dry::Types::CoercionError, /percentage must be less than or equal to 100/)
    end
  end

  it "coerces and validates basis and transitions" do
    aggregate_failures do
      expect(described_class::Basis["invoice_total"]).to eq(:invoice_total)
      expect(described_class::Transition["repeat"]).to eq(:repeat)
      expect { described_class::Basis[:unknown] }.to raise_error(Dry::Types::CoercionError, /basis must be one of/)
      expect { described_class::Transition[:jump] }.to raise_error(Dry::Types::CoercionError, /transition must be one of/)
    end
  end

  it "validates non-negative integer values" do
    aggregate_failures do
      expect(described_class::NonNegativeInteger["10"]).to eq(10)
      expect { described_class::NonNegativeInteger[-1] }.to raise_error(Dry::Types::CoercionError, /integer must be greater than or equal to 0/)
    end
  end

  it "validates decision status and reason values" do
    aggregate_failures do
      expect(described_class::DecisionStatus["scheduled"]).to eq(:scheduled)
      expect(described_class::DecisionReason["initial_attempt_failed"]).to eq(:initial_attempt_failed)
      expect(described_class::DecisionReason["invoice_not_retryable"]).to eq(:invoice_not_retryable)
      expect { described_class::DecisionStatus[:unknown] }.to raise_error(Dry::Types::CoercionError, /decision status/)
      expect { described_class::DecisionReason[:unknown] }.to raise_error(Dry::Types::CoercionError, /decision reason/)
    end
  end
end
