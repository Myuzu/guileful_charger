# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require "open3"

RSpec.describe "Sorbet boot configuration" do # rubocop:disable RSpec/DescribeClass
  let(:boot) { File.expand_path("../../../config/boot.rb", __dir__) }
  let(:application) { File.expand_path("../../../config/application.rb", __dir__) }
  let(:keys) { %w[BUNDLE_GEMFILE RAILS_ENV RACK_ENV SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS] }

  before do
    # Exercise boot's assignments in-process without installing global cache hooks.
    # Fresh-process examples below exercise the real requires.
    allow(TOPLEVEL_BINDING.receiver).to receive(:require).and_call_original
    allow(TOPLEVEL_BINDING.receiver).to receive(:require).with("bootsnap/setup").and_return(false)
  end

  around do |example|
    previous = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV.delete(key) }
    example.run
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  it "defers runtime policy to Rails without synthesizing environment settings" do
    load boot

    expect(ENV).not_to have_key("SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL")
    expect(ENV).not_to have_key("SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS")
  end

  it "preserves explicit operator overrides" do
    ENV["SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL"] = "always"
    ENV["SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS"] = "enabled"
    load boot

    expect(ENV.fetch("SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL")).to eq("always")
    expect(ENV.fetch("SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS")).to eq("enabled")
  end

  it "checks mismatches in fresh development/test processes and allows them in production" do
    script = <<~RUBY
      settings = ENV.to_h.select { |key, _| key.start_with?("SORBET_RUNTIME_") }
      require ARGV.fetch(0)
      abort "Environment changed" unless ENV.to_h.select { |key, _| key.start_with?("SORBET_RUNTIME_") } == settings
      require "sorbet-runtime"
      class InvalidReturn
        extend T::Sig
        sig { returns(Integer) }
        def self.call = "value"
      end
      begin
        puts InvalidReturn.call
      rescue TypeError
        puts "checked"
      end
    RUBY
    { "development" => "checked", "test" => "checked", "production" => "value" }.each do |environment, expected|
      env = keys.to_h { |key| [ key, nil ] }.merge("RAILS_ENV" => environment)
      output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, application)
      expect(status).to be_success, output
      expect(output.strip).to eq(expected)
    end
  end

  it "does not pass generated checking settings from local processes to production children" do
    script = <<~RUBY
      require ARGV.fetch(0)
      require "open3"
      probe = <<~CHILD
        require ARGV.fetch(0)
        class ChildProbe
          extend T::Sig
          sig { returns(Integer) }
          def self.call = "unchecked"
        end
        puts ChildProbe.call
      CHILD
      output, status = Open3.capture2e({ "RAILS_ENV" => "production" }, RbConfig.ruby, "-e", probe, ARGV.fetch(0))
      abort output unless status.success?
      puts output
    RUBY
    %w[development test].each do |environment|
      env = keys.to_h { |key| [ key, nil ] }.merge("RAILS_ENV" => environment)
      output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, application)
      expect(status).to be_success, output
      expect(output.strip).to eq("unchecked")
    end
  end

  it "warns local tools when a preloaded runtime already evaluated signatures" do
    script = <<~RUBY
      require "sorbet-runtime"
      T::Configuration.default_checked_level = :always
      class ToolProbe
        extend T::Sig
        sig { returns(String) }
        def self.call = "preloaded"
      end
      ToolProbe.call
      require ARGV.fetch(0)
      puts ToolProbe.call
    RUBY
    env = keys.to_h { |key| [ key, nil ] }.merge("RAILS_ENV" => "test")
    output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, application)

    expect(status).to be_success, output
    expect(output).to include("Sorbet runtime policy could not be applied", "preloaded")
  end

  it "honors an explicit default checked level in a fresh production process" do
    script = <<~RUBY
      require ARGV.fetch(0)
      class AlwaysProbe
        extend T::Sig
        sig { returns(Integer) }
        def self.call = "wrong"
      end
      begin
        AlwaysProbe.call
      rescue TypeError
        puts "checked"
      end
    RUBY
    env = keys.to_h { |key| [ key, nil ] }.merge("RAILS_ENV" => "production", "SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL" => "always")
    output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, application)

    expect(status).to be_success, output
    expect(output.strip).to eq("checked")
  end

  it "waits for production selected after boot, as with rails server -e production" do
    script = <<~RUBY
      require ARGV.fetch(0)
      ENV["RAILS_ENV"] = "production"
      require ARGV.fetch(1)
      class LateProductionProbe
        extend T::Sig
        sig { params(value: Integer).returns(String) }
        def self.call(value) = "unchecked"
      end
      puts LateProductionProbe.call("wrong type")
    RUBY
    env = keys.to_h { |key| [ key, nil ] }
    output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, boot, application)

    expect(status).to be_success, output
    expect(output.strip).to eq("unchecked")
  end

  it "applies production policy when sorbet-runtime was preloaded without evaluated signatures" do
    script = <<~RUBY
      require "sorbet-runtime"
      require ARGV.fetch(0)
      class PreloadedProbe
        extend T::Sig
        sig { params(value: Integer).returns(String) }
        def self.call(value) = "unchecked"
      end
      puts PreloadedProbe.call("wrong type")
    RUBY
    env = keys.to_h { |key| [ key, nil ] }.merge("RAILS_ENV" => "production")
    output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, application)

    expect(status).to be_success, output
    expect(output.strip).to eq("unchecked")
  end

  it "rejects production startup when evaluated preloaded signatures locked the default" do
    script = <<~RUBY
      require "sorbet-runtime"
      class LockedPolicyProbe
        extend T::Sig
        sig { params(value: Integer).returns(Integer) }
        def self.call(value) = value
      end
      LockedPolicyProbe.call(1)
      require ARGV.fetch(0)
      abort "Production booted with a locked runtime policy"
    RUBY
    env = keys.to_h { |key| [ key, nil ] }.merge("RAILS_ENV" => "production")
    output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, application)

    expect(status).not_to be_success
    expect(output).to include("SorbetRuntimeConfiguration::PolicyError", "Sorbet runtime policy could not be applied")
    expect(output).not_to include("Production booted with a locked runtime policy")
  end

  it "normalizes explicit false-like values instead of enabling production checks by presence" do
    script = <<~RUBY
      original = ENV["SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS"]
      require ARGV.fetch(0)
      abort "Operator input changed" unless ENV["SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS"] == original
      class FlagProbe
        extend T::Sig
        sig { returns(Integer) }
        def self.call = "unchecked"
      end
      begin
        puts FlagProbe.call
      rescue TypeError
        puts "checked"
      end
    RUBY
    { "0" => "unchecked", "false" => "unchecked", "" => "unchecked", " OFF " => "unchecked", "1" => "checked" }.each do |setting, expected|
      env = keys.to_h { |key| [ key, nil ] }.merge("RAILS_ENV" => "production", "SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS" => setting)
      output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, application)
      expect(status).to be_success, output
      expect(output.strip).to eq(expected)
    end
    env = keys.to_h { |key| [ key, nil ] }.merge("RAILS_ENV" => "development", "SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS" => "0")
    output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, application)
    expect(status).to be_success, output
    expect(output.strip).to eq("unchecked")
  end

  it "detects invalid lazy signatures before their first call even when production checks are off" do
    script = <<~RUBY
      require ARGV.fetch(0)
      require "sorbet-runtime"
      class InvalidLazySignature
        extend T::Sig
        sig { returns(Object.const_get("MissingRuntimeSignatureType")) }
        def self.call = 42
      end
      begin
        T::Utils.run_all_sig_blocks
      rescue NameError => error
        abort error.message unless error.name == :MissingRuntimeSignatureType
        puts "caught before first call"
      end
    RUBY
    env = keys.to_h { |key| [ key, nil ] }.merge("RAILS_ENV" => "production")
    output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, application)

    expect(status).to be_success, output
    expect(output.strip).to eq("caught before first call")
  end
end
