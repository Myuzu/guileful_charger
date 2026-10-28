# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require "open3"
require_relative "../../../lib/dry_type_catalog"

RSpec.describe DryTypeCatalog do
  it "creates independent nested namespaces for every includer" do
    first = Module.new { include ::DryTypeCatalog }
    second = Module.new { include ::DryTypeCatalog }
    shared = Module.new { include first }

    expect(first::Strict).not_to equal(second::Strict)
    expect(first::Coercible).not_to equal(second::Coercible)
    expect(first::Params).not_to equal(second::Params)
    first.const_set(:ApplicationOnlyProbe, first::String)
    first::Strict.const_set(:MoneyProbe, first::String)
    expect(shared::ApplicationOnlyProbe).to equal(first::String)
    expect(shared::Strict::MoneyProbe).to equal(first::String)
    expect { second::ApplicationOnlyProbe }.to raise_error(NameError)
    expect { second::Strict::MoneyProbe }.to raise_error(NameError)
    expect { described_class::Strict::MoneyProbe }.to raise_error(NameError)
  end

  it "loads Rebilling types without Rails and isolates them from global application extensions" do
    script = <<~RUBY
      require ARGV.fetch(0)
      abort "Rails initializer required" if defined?(::Types)
      abort "Wrong primitive" unless Rebilling::Types::Coercible::Integer["42"] == 42
      abort "Missing builder" unless Rebilling::Types.Instance(::String)["value"] == "value"
      module Types
        include ::DryTypeCatalog
        ApplicationOnly = DryTypeCatalog::String
        module Strict
          Money = DryTypeCatalog::String
        end
      end
      abort "Reopening hid primitives" unless Types::Strict::Integer[42] == 42
      abort "Extension missing" unless Types::Strict::Money["amount"] == "amount"
      abort "Application extension leaked" if Rebilling::Types.const_defined?(:ApplicationOnly)
      abort "Nested extension leaked" if Rebilling::Types::Strict.const_defined?(:Money)
      puts "standalone and isolated"
    RUBY
    path = File.expand_path("../../../app/services/rebilling/types.rb", __dir__)
    output, status = Open3.capture2e(RbConfig.ruby, "-e", script, path)

    expect(status).to be_success, output
    expect(output.strip).to eq("standalone and isolated")
  end
end
