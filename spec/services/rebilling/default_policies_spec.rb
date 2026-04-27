# rubocop:disable RSpec/DescribeClass
require "rails_helper"

RSpec.describe "Rebilling default policies" do
  it "defaults post-exhaustion handling to pausing the subscription" do
    expect(Rebilling::PostExhaustionPolicy.new.handle(nil, :max_attempts_reached)).to eq(:pause_subscription)
  end

  it "records decisions as a no-op" do
    expect(Rebilling::DecisionRecorder.new.record(:context, :decision)).to be_nil
  end

  it "returns nil scores for every candidate step by default" do
    step = Rebilling::RetryStep.new(percentage: 25, delay: 1.minute)

    expect(Rebilling::ScoringPolicy.new.score(:context, [ step ])).to eq(step.key => nil)
  end
end
