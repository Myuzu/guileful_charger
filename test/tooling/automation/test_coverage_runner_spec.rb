# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers
require "spec_helper"
require "stringio"
require "tmpdir"
require_relative "../../../script/test_coverage_runner"

RSpec.describe TestCoverageRunner do
  let(:output) { StringIO.new }
  let(:runner) { class_double(RSpec::Core::Runner, run: 0) }
  let(:coverage) { class_double(Coverage, result: results) }
  let(:files) { described_class::PROFILES.fetch("automation").fetch(:files) }
  let(:results) { files.to_h { |path| [ File.expand_path(path), { lines: [ nil, 1, 2 ] } ] } }

  def run_profile(name = "automation")
    described_class.run([ name ], coverage: coverage, runner: runner, output: output)
  end

  it "runs the selected specs and reports complete coverage" do
    expect(run_profile).to eq(0)
    expect(runner).to have_received(:run).with([ "test/tooling/automation" ])
    files.each { |path| expect(output.string).to include("#{path}: 100% line coverage") }
  end

  it "preserves failed spec status even when coverage is complete" do
    allow(runner).to receive(:run).and_return(2)

    expect(run_profile).to eq(2)
  end

  it "fails with the executable line numbers that were missed" do
    results[File.expand_path(files.first)][:lines] = [ nil, 0, 1, 0 ]
    results[File.expand_path(files.last)][:lines] = [ nil, 0 ]

    expect(run_profile).to eq(1)
    expect(output.string).to include("Uncovered lines in #{files.first}: 2, 4")
    expect(output.string).to include("Uncovered lines in #{files.last}: 2")
  end

  it "looks up real coverage paths when the configured file is a symlink" do
    Dir.mktmpdir("coverage-paths") do |directory|
      link = File.join(directory, "publisher.rb")
      File.symlink(File.realpath(files.first), link)
      stub_const("TestCoverageRunner::PROFILES", "linked" => { specs: [], files: [ link ] })

      expect(run_profile("linked")).to eq(0)
      expect(output.string).to include("#{link}: 100% line coverage")
    end
  end

  it "fails when a required file is absent or has no executable lines" do
    [ nil, [ nil ] ].each do |lines|
      results[File.expand_path(files.first)] = { lines: lines }
      expect(run_profile).to eq(1)
    end
    expect(output.string).to include("No executable coverage for #{files.first}")
  end

  it "rejects missing and unknown profiles without running specs" do
    expect(run_profile("unknown")).to eq(1)
    expect(described_class.run([], coverage: coverage, runner: runner, output: output)).to eq(1)
    expect(output.string).to include("Select a coverage profile: automation, runtime, compiler")
    expect(runner).not_to have_received(:run)
  end
end
