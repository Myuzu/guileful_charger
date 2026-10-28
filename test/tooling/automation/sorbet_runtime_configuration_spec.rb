# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require "sorbet-runtime"
require_relative "../../../lib/sorbet_runtime_configuration"

RSpec.describe SorbetRuntimeConfiguration do
  let(:runtime) { class_double(T::Configuration) }
  let(:keys) { %w[SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS] }

  around do |example|
    previous = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV.delete(key) }
    example.run
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  before do
    stub_const("T::Configuration", runtime)
    allow(runtime).to receive(:default_checked_level=)
    allow(runtime).to receive(:enable_checking_for_sigs_marked_checked_tests)
    allow(described_class).to receive(:require).with("sorbet-runtime")
  end

  it "configures an already loaded runtime instead of skipping its policy" do
    described_class.configure!(local: false)

    expect(runtime).to have_received(:default_checked_level=).with(:tests)
    expect(runtime).not_to have_received(:enable_checking_for_sigs_marked_checked_tests)
    expect(ENV.values_at(*keys)).to eq([ nil, nil ])
  end

  it "enables test-level checks locally without passing generated settings to children" do
    described_class.configure!(local: true)

    expect(runtime).to have_received(:enable_checking_for_sigs_marked_checked_tests)
    expect(ENV.values_at(*keys)).to eq([ nil, nil ])
  end

  it "preserves an explicit default level and enabling flag" do
    ENV["SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL"] = "always"
    ENV["SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS"] = "1"
    described_class.configure!(local: false)

    expect(runtime).not_to have_received(:default_checked_level=)
    expect(runtime).to have_received(:enable_checking_for_sigs_marked_checked_tests)
    expect(ENV.values_at(*keys)).to eq(%w[always 1])
  end

  it "normalizes a disabled flag only while requiring a fresh runtime" do
    hide_const("T::Configuration")
    ENV["SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS"] = " OFF "
    allow(described_class).to receive(:require).with("sorbet-runtime") do
      expect(ENV).not_to have_key("SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS")
      stub_const("T::Configuration", runtime)
    end
    described_class.configure!(local: false)

    expect(ENV.fetch("SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS")).to eq(" OFF ")
    expect(runtime).to have_received(:default_checked_level=).with(:tests)
    expect(runtime).not_to have_received(:enable_checking_for_sigs_marked_checked_tests)
  end

  it "restores operator input when the runtime cannot be loaded" do
    ENV["SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS"] = "0"
    allow(described_class).to receive(:require).and_raise(LoadError, "missing Sorbet")

    expect { described_class.configure!(local: false) }.to raise_error(LoadError, "missing Sorbet")
    expect(ENV.fetch("SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS")).to eq("0")
  end

  it "stops production boot if signatures already locked the default" do
    allow(runtime).to receive(:default_checked_level=).and_raise(RuntimeError, "Set the default checked level earlier")

    expect { described_class.configure!(local: false) }
      .to raise_error(described_class::PolicyError, /Set the default checked level earlier.*before preloading/)
  end

  it "warns local tools when their evaluated signatures prevent reconfiguration" do
    allow(runtime).to receive(:default_checked_level=).and_raise(RuntimeError, "locked default")
    allow(described_class).to receive(:warn)
    described_class.configure!(local: true)

    expect(described_class).to have_received(:warn).with(/Sorbet runtime policy could not be applied: locked default/)
  end

  it "stops production when a preloader already enabled a false-like flag by presence" do
    ENV["SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS"] = "0"

    expect { described_class.configure!(local: false) }
      .to raise_error(described_class::PolicyError, /already interpreted the disabled checking flag as enabled/)
    expect(ENV.fetch("SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS")).to eq("0")
  end
end
