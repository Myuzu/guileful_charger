# typed: false

require "rails_helper"

RSpec.describe Rebilling::PostExhaustionPolicy do
  subject(:policy) { described_class.new }

  it "returns the placeholder action for a nil invoice" do
    expect(policy.handle(nil, :max_attempts_reached)).to eq(:pause_subscription)
  end

  it "ignores both arguments without requiring invoice or reason methods" do
    [ nil, :placeholder, 42, BasicObject.new ].each do |input|
      expect(policy.handle(input, input)).to eq(:pause_subscription)
    end
  end
end
