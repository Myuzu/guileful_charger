# typed: false

require "spec_helper"

RSpec.describe "Tooling process isolation" do # rubocop:disable RSpec/DescribeClass
  it "does not make Sorbet sig available on every application class" do
    expect(Class.new.respond_to?(:sig, true)).to be(false)
  end
end
