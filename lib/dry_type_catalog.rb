# typed: ignore

require "dry-types"

# Shared dry-rb primitives. Application-specific Types extensions stay outside
# this catalog so they do not become implicit Rebilling inputs.
module DryTypeCatalog
  include Dry.Types

  def self.included(namespace)
    super
    return if namespace.instance_variable_defined?(:@dry_type_catalog_initialized)

    # Fresh nested modules prevent extensions such as Types::Strict::Money from
    # changing sibling namespaces. Validator objects themselves are immutable.
    fresh = Dry.Types
    namespace.include(fresh)
    fresh.constants.each do |name|
      value = fresh.const_get(name)
      # Own nested constants make normal `module Strict` reopening safe.
      namespace.const_set(name, value) if value.is_a?(::Module) && !value.is_a?(::Class)
    end
    namespace.instance_variable_set(:@dry_type_catalog_initialized, true)
  end
end
