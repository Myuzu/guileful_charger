# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers
require "spec_helper"
require "stringio"
require "tmpdir"
require "open3"
require_relative "../../../script/test_coverage_runner"

RSpec.describe TestCoverageRunner do
  let(:output) { StringIO.new }
  let(:runner) { class_double(RSpec::Core::Runner, run: 0) }
  let(:coverage) { class_double(Coverage, result: results, peek_result: results) }
  let(:files) { described_class::PROFILES.fetch("automation").fetch(:files) }
  let(:results) { files.to_h { |path| [ File.expand_path(path, described_class::ROOT), { lines: [ nil, 1, 2 ] } ] } }

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

  it "only stops coverage when this runner owns it" do
    expect(run_profile).to eq(0)
    expect(coverage).to have_received(:peek_result).once
    expect(coverage).not_to have_received(:result)
    expect(described_class.run([ "automation" ], owns_coverage: true, coverage: coverage, runner: runner, output: output)).to eq(0)
    expect(coverage).to have_received(:result).once
  end

  it "leaves a real outer coverage session active with its counters intact" do
    Dir.mktmpdir("outer-coverage") do |directory|
      probe = File.join(directory, "probe.rb")
      File.write(probe, "value = 1\n")
      script = <<~RUBY
        require "coverage"
        Coverage.start(lines: true)
        load ARGV.fetch(0)
        require ARGV.fetch(1)
        TestCoverageRunner.send(:remove_const, :PROFILES)
        TestCoverageRunner::PROFILES = {"outer" => {specs: [], files: [ARGV.fetch(0)]}}
        runner = Object.new
        def runner.run(*) = 0
        abort "profile failed" unless TestCoverageRunner.run(["outer"], runner: runner) == 0
        abort "outer coverage stopped" unless Coverage.running?
        abort "outer counters cleared" unless Coverage.peek_result.fetch(ARGV.fetch(0))[:lines] == [1]
      RUBY
      implementation = File.join(described_class::ROOT, "script/test_coverage_runner.rb")
      output, status = Open3.capture2e(RbConfig.ruby, "-e", script, probe, implementation)

      expect(status).to be_success, output
    end
  end

  it "resolves profile files and runs specs from the project root when invoked elsewhere" do
    Dir.mktmpdir("coverage-cwd") do |directory|
      allow(runner).to receive(:run) { expect(Dir.pwd).to eq(File.realpath(described_class::ROOT)); 0 }
      Dir.chdir(directory) do
        expect(run_profile).to eq(0)
        expect(Dir.pwd).to eq(File.realpath(directory))
      end
    end
  end

  it "reports a missing profile file and continues reporting the remaining files" do
    stub_const("TestCoverageRunner::PROFILES", "missing" => { specs: [], files: [ "missing.rb", files.first ] })
    expect(run_profile("missing")).to eq(1)
    expect(output.string).to include("No executable coverage for missing.rb", "#{files.first}: 100% line coverage")
  end

  it "accepts line arrays from an outer harness using Coverage.start without options" do
    results.transform_values! { |entry| entry.fetch(:lines) }

    expect(run_profile).to eq(0)
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
    expect(output.string).to include("Select a coverage profile: automation, compiler")
    expect(runner).not_to have_received(:run)
  end
end
