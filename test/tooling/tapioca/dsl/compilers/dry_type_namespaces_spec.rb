# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require_relative "../../../../../spec/rails_helper"
require "tapioca/internal"
require "tmpdir"
require "open3"
require_relative "../../../../../sorbet/tapioca/compilers/dry_type_namespaces"

RSpec.describe Tapioca::Dsl::Compilers::DryTypeNamespaces do
  let(:pipeline) { Tapioca::Dsl::Pipeline.new(requested_constants: described_class.gather_constants) }

  it "discovers both namespaces and generates the complete shared validator catalog" do
    expect(described_class.gather_constants).to include(::Types, ::Rebilling::Types)

    [ ::Types, ::Rebilling::Types ].each do |namespace|
      file = RBI::File.new(strictness: "true")
      compiler = described_class.new(pipeline, file.root, namespace)
      compiler.decorate
      rendered = file.string

      expect(rendered).to include("Integer = T.let(T.unsafe(nil), T.untyped)")
      expect(rendered).to include("extend ::Dry::Types::BuilderMethods")
      expect(rendered).to include("module Coercible", "module Nominal", "module Optional")
      expect(rendered).not_to include("VALID_BASES", "Basis =")
    end
  end

  it "discovers additional modules that include the shared catalog" do
    additional = Module.new { include ::Types }
    stub_const("AdditionalTypes", additional)
    described_class.reset_state

    expect(described_class.gather_constants).to include(additional)
  ensure
    described_class.reset_state
  end

  it "reflects new validators in both namespaces and skips helper values and classes" do
    stub_const("Types::NewValidator", ::Types::String)
    stub_const("Types::HelperValue", 42)
    stub_const("Types::HelperClass", Class.new)

    [ ::Types, ::Rebilling::Types ].each do |namespace|
      file = RBI::File.new(strictness: "true")
      described_class.new(pipeline, file.root, namespace).decorate

      expect(file.string).to include("NewValidator = T.let(T.unsafe(nil), T.untyped)")
      expect(file.string).not_to include("HelperValue", "HelperClass")
    end
  end

  it "exposes builder methods on both namespaces to the static checker" do
    Dir.mktmpdir("dry-types-probe") do |directory|
      probe = File.join(directory, "builders.rb")
      File.write(probe, "# typed: true\nTypes.Instance(::String)\nRebilling::Types.Instance(::String)\nTypes.Array(Types::String)\n")
      output, status = Open3.capture2e(RbConfig.ruby, Gem.bin_path("sorbet", "srb"), "tc", "--file", probe)

      expect(status).to be_success, output
    end
  end
end
