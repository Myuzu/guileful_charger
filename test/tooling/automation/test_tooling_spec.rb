# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require_relative "../../../script/test_coverage_runner"

RSpec.describe "Tooling entrypoint" do # rubocop:disable RSpec/DescribeClass
  let(:entrypoint) { File.expand_path("../../../bin/test_tooling", __dir__) }

  before do
    stub_const("ARGV", [ "automation" ])
    allow(TestCoverageRunner).to receive(:run).with([ "automation" ], owns_coverage: anything).and_return(7)
  end

  it "sets up Bundler and starts coverage before forwarding arguments and exit status" do
    allow(Coverage).to receive(:running?).and_return(false)
    allow(Coverage).to receive(:start)

    expect { load entrypoint }.to raise_error(SystemExit) { |error| expect(error.status).to eq(7) }
    expect(Coverage).to have_received(:start).with(lines: true)
    expect(TestCoverageRunner).to have_received(:run).with([ "automation" ], owns_coverage: true)
    expect(Gem.loaded_specs).to have_key("bundler")
  end

  it "preserves coverage already started by a calling harness" do
    allow(Coverage).to receive(:running?).and_return(true)
    allow(Coverage).to receive(:start)

    expect { load entrypoint }.to raise_error(SystemExit) { |error| expect(error.status).to eq(7) }
    expect(Coverage).not_to have_received(:start)
    expect(TestCoverageRunner).to have_received(:run).with([ "automation" ], owns_coverage: false)
  end

  it "preloads the compiler's standalone dependencies before starting coverage" do
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
