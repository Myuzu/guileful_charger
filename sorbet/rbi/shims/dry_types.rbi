# typed: true

# Dry.Types creates these namespaces and type objects at runtime. These are
# dry-rb validators, NOT Ruby classes or Sorbet type aliases. Keep the objects
# untyped: constructor/coercion results require explicit method signatures.
# Add constants here as the application starts using more of the dry-types API.
module Types
  Array = T.let(T.unsafe(nil), T.untyped)
  Bool = T.let(T.unsafe(nil), T.untyped)
  Hash = T.let(T.unsafe(nil), T.untyped)
  Integer = T.let(T.unsafe(nil), T.untyped)
  Nil = T.let(T.unsafe(nil), T.untyped)

  module Coercible
    Integer = T.let(T.unsafe(nil), T.untyped)
    String = T.let(T.unsafe(nil), T.untyped)
    Symbol = T.let(T.unsafe(nil), T.untyped)
  end

  module Nominal
    Any = T.let(T.unsafe(nil), T.untyped)
  end
end

# Ruby resolves these through the included Types module. Sorbet needs explicit
# aliases when callers qualify them as Rebilling::Types::Coercible, etc.
module Rebilling::Types
  Array = ::Types::Array
  Bool = ::Types::Bool
  Hash = ::Types::Hash
  Nil = ::Types::Nil
  Coercible = ::Types::Coercible
  Nominal = ::Types::Nominal
end
