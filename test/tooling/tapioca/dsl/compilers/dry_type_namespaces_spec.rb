# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require "tapioca/internal"
require "tmpdir"
require "open3"
require_relative "../../../../../config/initializers/dry"
require_relative "../../../../../app/services/rebilling/types"
require_relative "../../../../../sorbet/tapioca/compilers/dry_type_namespaces"

RSpec.describe Tapioca::Dsl::Compilers::DryTypeNamespaces do
  let(:pipeline) { Tapioca::Dsl::Pipeline.new(requested_constants: described_class.gather_constants) }

  it "discovers both namespaces and generates the complete shared validator catalog" do
    expect(described_class.gather_constants).to include(::DryTypeCatalog, ::Types, ::Rebilling::Types)

    [ ::DryTypeCatalog, ::Types, ::Rebilling::Types ].each do |namespace|
      file = RBI::File.new(strictness: "true")
      compiler = described_class.new(pipeline, file.root, namespace)
      compiler.decorate
      rendered = file.string

      expect(rendered).to include("Integer = T.let(T.unsafe(nil), T.untyped)")
      expect(rendered).to include("extend ::Dry::Types::BuilderMethods")
      expect(rendered).to include("module Coercible", "module Nominal", "module Optional")
      expect(rendered).not_to include("VALID_BASES")
      expect(rendered).to include("Basis =") if namespace == ::Rebilling::Types
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
    stub_const("DryTypeCatalog::NewValidator", ::Types::String)
    stub_const("DryTypeCatalog::HelperValue", 42)
    stub_const("DryTypeCatalog::HelperClass", Class.new)

    [ ::Types, ::Rebilling::Types ].each do |namespace|
      file = RBI::File.new(strictness: "true")
      described_class.new(pipeline, file.root, namespace).decorate

      expect(file.string).to include("NewValidator = T.let(T.unsafe(nil), T.untyped)")
      expect(file.string).not_to include("HelperValue", "HelperClass")
    end
  end

  it "exposes builder methods on both namespaces to the static checker" do
    stub_const("Types::Email", ::Types::String)
    admin = Module.new { include ::Types }
    stub_const("AdminTypes", admin)
    Dir.mktmpdir("dry-types-probe") do |directory|
      probe = File.join(directory, "builders.rb")
      File.write(probe, "# typed: true\nTypes.Instance(::String)\nRebilling::Types.Instance(::String)\nTypes.Array(Types::String)\nAdminTypes::Email\n")
      interface = RBI::File.new(strictness: "true")
      [ ::DryTypeCatalog, ::Types, ::Rebilling::Types, admin ].each do |namespace|
        described_class.new(pipeline, interface.root, namespace).decorate
      end
      namespace_rbi = File.join(directory, "namespaces.rbi")
      File.write(namespace_rbi, interface.string)
      version = Gem.loaded_specs.fetch("dry-types").version
      gem_rbi = File.expand_path("../../../../../sorbet/rbi/gems/dry-types@#{version}.rbi", __dir__)
      builder = RBI::Parser.parse_file(gem_rbi).nodes.find { |node| node.is_a?(RBI::Module) && node.name == "Dry::Types::BuilderMethods" }
      builder_rbi = File.join(directory, "builders.rbi")
      File.write(builder_rbi, "# typed: true\nmodule Dry; module Types; end; end\nmodule Rebilling; end\n#{builder.string}")
      File.write(File.join(directory, "unrelated.rb"), "# typed: true\nUnknownUnrelatedConstant.call\n")
      output, status = Open3.capture2e(RbConfig.ruby, Gem.bin_path("sorbet", "srb"), "tc", "--no-config", probe, namespace_rbi, builder_rbi, chdir: directory)

      expect(status).to be_success, output
    end
  end
end
