# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require "yaml"

RSpec.describe "CI permissions" do # rubocop:disable RSpec/DescribeClass
  it "limits App-triggered CI to read-only tokens without persisted Git credentials" do
    %w[ci brakeman].each do |name|
      workflow = YAML.load_file(File.expand_path("../../../.github/workflows/#{name}.yml", __dir__))
      expect(workflow.fetch("permissions")).to eq("contents" => "read")
      jobs = workflow.fetch("jobs").values
      checkouts = jobs.flat_map { |job| job.fetch("steps") }.select { |step| step["uses"].to_s.start_with?("actions/checkout@") }
      expect(checkouts).not_to be_empty
      expect(checkouts).to all(include("with" => include("persist-credentials" => false)))
    end
  end

  it "keeps independent check names while sharing setup through a fail-independent matrix" do
    workflow = YAML.load_file(File.expand_path("../../../.github/workflows/ci.yml", __dir__))
    job = workflow.fetch("jobs").fetch("checks")
    expect(job.fetch("name")).to eq("${{ matrix.name }}")
    expect(job.dig("strategy", "fail-fast")).to be(false)
    expect(job.dig("strategy", "matrix", "include").map { |entry| entry.fetch("name") }).to contain_exactly("scan_ruby", "lint", "automation", "compiler", "typecheck")
    expect(workflow.fetch("jobs").fetch("test").fetch("steps")).to include(include("run" => "bin/rspec"))
  end
end
