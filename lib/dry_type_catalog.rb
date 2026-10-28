# typed: ignore

require "dry-types"

# Shared dry-rb primitives. Application-specific Types extensions stay outside
# this catalog so they do not become implicit Rebilling inputs.
module DryTypeCatalog
  include Dry.Types

  def self.included(namespace)
    super
    # Fresh nested modules prevent extensions such as Types::Strict::Money from
    # changing sibling namespaces. Validator objects themselves are immutable.
    namespace.include(Dry.Types)
  end
end
