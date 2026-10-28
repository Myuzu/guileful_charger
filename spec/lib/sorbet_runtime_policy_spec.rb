# typed: false

# rubocop:disable RSpec/MultipleExpectations
require "rails_helper"

module SorbetPolicySpec
  class InvalidReturn
    extend T::Sig

    sig { returns(Integer) }
    def call
      "sensitive billing value"
    end
  end
end

RSpec.describe SorbetRuntimePolicy do
  around do |example|
    previous_handler = T::Configuration.instance_variable_get(:@call_validation_error_handler)
    T::Configuration.call_validation_error_handler = nil
    example.run
  ensure
    T::Configuration.call_validation_error_handler = previous_handler
  end

  it "reports production mismatches without raising or logging billing values" do
    allow(Rails.logger).to receive(:error)
    described_class.configure(production: true, logger: Rails.logger)

    expect(SorbetPolicySpec::InvalidReturn.new.call).to eq("sensitive billing value")
    expect(Rails.logger).to have_received(:error).with("Sorbet signature mismatch: SorbetPolicySpec::InvalidReturn#call (Return value)")
  end

  it "retains raising behavior outside production" do
    described_class.configure(production: false, logger: Rails.logger)

    expect { SorbetPolicySpec::InvalidReturn.new.call }.to raise_error(TypeError)
  end
end
