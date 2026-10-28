# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require "open3"
require_relative "../../../script/test_coverage_runner"

RSpec.describe "Tooling entrypoint" do # rubocop:disable RSpec/DescribeClass
  let(:entrypoint) { File.expand_path("../../../bin/test_tooling", __dir__) }

  def launch_child(outer:)
    script = <<~RUBY_CODE
      require "coverage"
      outer = ARGV.shift == "outer"
      Coverage.start(lines: true) if outer
      entrypoint = ARGV.shift
      require ARGV.shift
      TestCoverageRunner.define_singleton_method(:run) do |args, owns_coverage:|
        abort "wrong coverage owner" unless owns_coverage == !outer
        abort "coverage not running" unless Coverage.running?
        abort "Bundler missing" unless Gem.loaded_specs.key?("bundler")
        unless outer
          measured = Coverage.peek_result.keys
          abort "Dependency boot instrumented" if measured.any? { |path| path.match?(%r{/gems/(?:rspec-|json-|open3-)}) }
        end
        puts args.join(" ")
        7
      end
      ARGV.replace(["automation", "--seed", "123"])
      load entrypoint
    RUBY_CODE
    implementation = File.expand_path("../../../script/test_coverage_runner.rb", __dir__)
    Open3.capture2e(RbConfig.ruby, "-e", script, outer ? "outer" : "owned", entrypoint, implementation)
  end

  it "sets up Bundler, starts coverage, and forwards arguments and exit status" do
    output, status = launch_child(outer: false)

    expect(status.exitstatus).to eq(7), output
    expect(output.strip).to eq("automation --seed 123")
  end

  it "preserves coverage already started by a calling harness" do
    output, status = launch_child(outer: true)

    expect(status.exitstatus).to eq(7), output
    expect(output.strip).to eq("automation --seed 123")
  end

  it "preloads compiler dependencies before starting coverage" do
    # Load once in this process: Ruby resets a file's counters on each load.
    # Other entrypoint scenarios run in child processes, regardless of test order.
    stub_const("ARGV", [ "compiler" ])
    main = TOPLEVEL_BINDING.receiver
    allow(main).to receive(:require).and_call_original
    allow(main).to receive(:require).with("tapioca/internal").and_return(false)
    allow(main).to receive(:require_relative).and_return(false)
    allow(Coverage).to receive(:running?).and_return(false)
    allow(Coverage).to receive(:start)
    allow(TestCoverageRunner).to receive(:run).with([ "compiler" ], owns_coverage: true).and_return(0)

    expect { load entrypoint }.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
    expect(main).to have_received(:require).with("tapioca/internal").ordered
    expect(Coverage).to have_received(:start).with(lines: true).ordered
  end
end
