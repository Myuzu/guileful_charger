# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
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
    handlers = %i[call_validation_error_handler sig_builder_error_handler sig_validation_error_handler]
    previous = handlers.to_h { |name| [ name, T::Configuration.instance_variable_get("@#{name}") ] }
    handlers.each { |name| T::Configuration.public_send("#{name}=", nil) }
    example.run
  ensure
    previous.each { |name, value| T::Configuration.public_send("#{name}=", value) }
  end

  it "reports production mismatches without raising or logging billing values" do
    allow(Rails.logger).to receive(:error)
    described_class.configure(production: true, logger: Rails.logger)

    expect(SorbetPolicySpec::InvalidReturn.new.call).to eq("sensitive billing value")
    expect(Rails.logger).to have_received(:error).with(/Sorbet Return value: SorbetPolicySpec::InvalidReturn#call at .*sorbet_runtime_policy_spec.rb:\d+/)
  end

  it "retains raising behavior outside production" do
    described_class.configure(production: false, logger: Rails.logger)

    expect { SorbetPolicySpec::InvalidReturn.new.call }.to raise_error(TypeError)
  end

  it "reports malformed builders and invalid override signatures without aborting their methods" do
    allow(Rails.logger).to receive(:error)
    described_class.configure(production: true, logger: Rails.logger)
    builder = Class.new do
      extend T::Sig
      public_send(:sig) { params(value: Integer) }
      define_method(:call) { |value| value }
    end
    invalid = Class.new do
      extend T::Sig
      public_send(:sig) { override.returns(Integer) }
      define_method(:call) { 42 }
    end

    expect(builder.new.call(42)).to eq(42)
    expect(invalid.new.call).to eq(42)
    expect(Rails.logger).to have_received(:error).with(/Sorbet sig builder/)
    expect(Rails.logger).to have_received(:error).with(/Sorbet sig validation/)
  end

  it "keeps Ruby exceptions inside lazy sig blocks visible" do
    described_class.configure(production: true, logger: Rails.logger)
    klass = Class.new do
      extend T::Sig
      public_send(:sig) { returns(Object.const_get("MissingRuntimeSigType")) }
      define_method(:call) { 42 }
    end

    expect { klass.new.call }.to raise_error(NameError, /MissingRuntimeSigType/)
  end

  it "accepts a missing signature from generated property methods" do
    allow(Rails.logger).to receive(:error)
    described_class.configure(production: true, logger: Rails.logger)
    T::Configuration.call_validation_error_handler(nil, kind: "Property", value: "private")

    expect(Rails.logger).to have_received(:error).with("Sorbet Property: unknown method")
  end
end
