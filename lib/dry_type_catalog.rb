# typed: ignore

require "dry-types"

# Shared dry-rb primitives. Application-specific Types extensions stay outside
# this catalog so they do not become implicit Rebilling inputs.
module DryTypeCatalog
  include Dry.Types
end
