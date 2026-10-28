# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require "open3"

RSpec.describe "Sorbet boot configuration" do # rubocop:disable RSpec/DescribeClass
  let(:boot) { File.expand_path("../../../config/boot.rb", __dir__) }
  let(:application) { File.expand_path("../../../config/application.rb", __dir__) }
  let(:keys) { %w[RAILS_ENV RACK_ENV SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS] }

  around do |example|
    previous = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV.delete(key) }
    example.run
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  it "sets the default level before gems load and defers environment selection to Rails" do
    load boot

    expect(ENV.fetch("SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL")).to eq("tests")
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
      require ARGV.fetch(0)
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

  it "waits for production selected after boot, as with rails server -e production" do
    script = <<~RUBY
      require ARGV.fetch(0)
      ENV["RAILS_ENV"] = "production"
      require ARGV.fetch(1)
      puts ENV.fetch("SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS", "disabled")
    RUBY
    env = keys.to_h { |key| [ key, nil ] }
    output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, boot, application)

    expect(status).to be_success, output
    expect(output.strip).to eq("disabled")
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
