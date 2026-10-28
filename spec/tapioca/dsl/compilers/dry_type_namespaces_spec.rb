# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"
require "tapioca/internal"
require_relative "../../../../sorbet/tapioca/compilers/dry_type_namespaces"

RSpec.describe Tapioca::Dsl::Compilers::DryTypeNamespaces do
  let(:pipeline) { Tapioca::Dsl::Pipeline.new(requested_constants: described_class.gather_constants) }

  it "discovers both namespaces and generates the complete shared validator catalog" do
    expect(described_class.gather_constants).to eq([ ::Types, ::Rebilling::Types ])

    described_class.gather_constants.each do |namespace|
      file = RBI::File.new(strictness: "true")
      compiler = described_class.new(pipeline, file.root, namespace)
      compiler.decorate
      rendered = file.string

      expect(rendered).to include("Integer = T.let(T.unsafe(nil), T.untyped)")
      expect(rendered).to include("module Coercible", "module Nominal", "module Optional")
      expect(rendered).not_to include("VALID_BASES", "Basis =")
    end
  end

  it "reflects new validators in both namespaces and skips helper values and classes" do
    stub_const("Types::NewValidator", ::Types::String)
    stub_const("Types::HelperValue", 42)
    stub_const("Types::HelperClass", Class.new)

    described_class.gather_constants.each do |namespace|
      file = RBI::File.new(strictness: "true")
      described_class.new(pipeline, file.root, namespace).decorate

      expect(file.string).to include("NewValidator = T.let(T.unsafe(nil), T.untyped)")
      expect(file.string).not_to include("HelperValue", "HelperClass")
    end
  end
end
