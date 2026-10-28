# typed: false
# frozen_string_literal: true

module Tapioca
  module Dsl
    module Compilers
      # Emit validator objects as untyped values, never as Ruby class aliases.
      # Both namespaces come from the same runtime catalog, so adding a dry-type
      # does not require maintaining duplicate constant lists.
      class DryTypeNamespaces < Compiler
        extend T::Generic
        ConstantType = type_member { { fixed: Module } }

        def self.gather_constants
          all_modules.select { |namespace| namespace == ::DryTypeCatalog || namespace < ::DryTypeCatalog }
        end

        def decorate
          root.create_path(constant) do |scope|
            scope.create_extend("::Dry::Types::BuilderMethods")
            emit_constants(scope, constant)
          end
        end

        private

        def emit_constants(scope, namespace)
          namespace.constants.sort.each do |name|
            value = namespace.const_get(name)
            case value
            when ::Dry::Types::Type
              scope.create_constant(name.to_s, value: "T.let(T.unsafe(nil), T.untyped)")
            when Module
              next if value.is_a?(Class)

              scope.create_module(name.to_s) { |nested| emit_constants(nested, value) }
            end
          end
        end
      end
    end
  end
end
