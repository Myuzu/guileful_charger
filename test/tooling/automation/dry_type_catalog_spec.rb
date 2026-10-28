# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require "open3"
require_relative "../../../lib/dry_type_catalog"

RSpec.describe DryTypeCatalog do
  it "creates independent nested namespaces for every includer" do
    stub_const("Money", Class.new)
    first = Module.new { include ::DryTypeCatalog }
    second = Module.new { include ::DryTypeCatalog }

    expect(first::Strict).not_to equal(second::Strict)
    expect(first::Coercible).not_to equal(second::Coercible)
    expect(first::Params).not_to equal(second::Params)
    first::Strict.const_set(:Money, first::String)
    expect(first::Strict::Money).to equal(first::String)
    expect(second::Strict.const_defined?(:Money)).to be(true)
    expect(second::Strict.const_defined?(:Money, false)).to be(false)
    expect(described_class::Strict.const_defined?(:Money, false)).to be(false)
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
      end
      Types::Strict.const_set(:Money, DryTypeCatalog::String)
      abort "Application extension leaked" if Rebilling::Types.const_defined?(:ApplicationOnly, false)
      abort "Nested extension leaked" if Rebilling::Types::Strict.const_defined?(:Money, false)
      puts "standalone and isolated"
    RUBY
    path = File.expand_path("../../../app/services/rebilling/types.rb", __dir__)
    output, status = Open3.capture2e(RbConfig.ruby, "-e", script, path)

    expect(status).to be_success, output
    expect(output.strip).to eq("standalone and isolated")
  end
end
