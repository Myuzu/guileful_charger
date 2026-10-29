# typed: false

require "rails_helper"

RSpec.describe Rebilling::ScoringPolicy do
  subject(:policy) { described_class.new }

  it "returns an empty map without consulting the ignored context" do
    [ nil, :context, BasicObject.new ].each do |context|
      expect(policy.score(context, [])).to eq({})
    end
  end

  it "maps distinct candidate keys to nil while accepting a frozen collection" do
    first = Rebilling::RetryStep.new(percentage: 25, delay: 60, key: :first)
    second = Rebilling::RetryStep.new(percentage: 50, delay: 60, key: :second)
    duplicate = Rebilling::RetryStep.new(percentage: 75, delay: 60, key: :first)
    candidates = [ first, second, duplicate ].freeze

    expect(policy.score(:context, candidates)).to eq(first: nil, second: nil)
  end

  it "returns independent result maps between calls" do
    first = policy.score(nil, [])
    first[:external] = 1

    expect(policy.score(nil, [])).to eq({})
  end
end
