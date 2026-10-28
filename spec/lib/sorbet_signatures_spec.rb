# typed: false

require "rails_helper"

RSpec.describe "Application signatures" do # rubocop:disable RSpec/DescribeClass
  it "builds every pending signature after eager loading the application" do
    Rails.application.eager_load!

    expect { T::Utils.run_all_sig_blocks }.not_to raise_error
  end
end
