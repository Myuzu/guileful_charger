require "rails_helper"

RSpec.describe Rebilling::Attempt do
  include RebillingHelpers

  it "rejects negative attempted amounts" do
    expect { build_attempt(amount_attempted_cents: -1) }.to raise_error(Dry::Types::CoercionError, /integer must be greater than or equal to 0/)
  end
end
