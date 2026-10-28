# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require "open3"
require_relative "../../../lib/dry_type_catalog"

RSpec.describe DryTypeCatalog do
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
      abort "Application extension leaked" if Rebilling::Types.const_defined?(:ApplicationOnly)
      puts "standalone and isolated"
    RUBY
    path = File.expand_path("../../../app/services/rebilling/types.rb", __dir__)
    output, status = Open3.capture2e(RbConfig.ruby, "-e", script, path)

    expect(status).to be_success, output
    expect(output.strip).to eq("standalone and isolated")
  end
end
