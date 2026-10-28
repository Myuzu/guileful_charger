# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe SorbetRuntimePolicy::Reporter do
  let(:logger) { instance_double(Logger, error: nil) }

  it "formats class and instance methods with source locations without inspecting objects" do
    reporter = described_class.new(logger, -> { 0 })
    signature = T::Utils.signature_for_method(Rebilling::Decision.method(:from_outcome))
    reporter.report(kind: "Return value", method: signature.method)
    object = Object.new
    def object.inspect = "private billing data"
    def object.call = nil
    reporter.report(kind: "Parameter", method: object.method(:call), location: caller_locations(0, 1).first)

    expect(logger).to have_received(:error).with(/Rebilling::Decision\.from_outcome at .*decision.rb:\d+/)
    expect(logger).to have_received(:error).with(/Object\.call at .*reporter_spec.rb:\d+/)
  end

  it "rate limits each method and kind across different callers, then permits another report" do
    now = 0
    reporter = described_class.new(logger, -> { now })
    method = Rebilling::Decision.method(:from_outcome)
    reporter.report(kind: "Return value", method: method, location: [ "one.rb", 1 ])
    reporter.report(kind: "Return value", method: method, location: [ "two.rb", 2 ])
    now = 60
    reporter.report(kind: "Return value", method: method)

    expect(logger).to have_received(:error).twice
  end

  it "bounds stored failures and handles anonymous owners without source locations" do
    stub_const("SorbetRuntimePolicy::Reporter::MAX_KEYS", 1)
    reporter = described_class.new(logger, -> { 0 })
    anonymous = Class.new { def call = nil }
    anonymous.define_singleton_method(:call) { nil }
    reporter.report(kind: "Return value", method: anonymous.instance_method(:call))
    reporter.report(kind: "Return value", method: anonymous.method(:call), location: Object.new)
    reporter.report(kind: "Property")

    expect(logger).to have_received(:error).with(/\(anonymous\)#call/)
    expect(logger).to have_received(:error).with("Sorbet Return value: (anonymous).call")
    expect(logger).to have_received(:error).with("Sorbet Property: unknown method")
  end
end
