# Type checking

[← README](../README.md) · [Development](development.md) · [Dependency automation](dependency-automation.md)

## Daily workflow

Sorbet checks Ruby statically; Tapioca generates Ruby interface files (RBIs) for
gems and Rails DSLs. Generated interfaces are committed so CI can detect drift.
Use Tapioca rather than the legacy `srb init`, following
[Sorbet's adoption guide](https://sorbet.org/docs/adopting).

| Check | Command | Database needed? |
| --- | --- | --- |
| Static types | `bundle exec srb tc` | No |
| Gem RBI versions | `bin/tapioca gems --verify` | No |
| Rails DSL interfaces | `CI=1 bin/tapioca dsl --verify` | Yes, prepared test DB |

Container equivalents are `make typecheck` and `make rbi-verify`. After dependency
or model/DSL changes:

```bash
bin/tapioca gems
RAILS_ENV=test bin/rails db:prepare
CI=1 bin/tapioca dsl
bundle exec srb tc
```

`CI=1` makes Rails eagerly load the same framework controllers locally and in CI.
Tapioca's [`dsl.environment: test`](../sorbet/tapioca/config.yml) controls the Rails
environment; setting `RAILS_ENV` on a DSL command does not override it. Test boot
does not connect Hutch to RabbitMQ.

> [!NOTE]
> `gems --verify` checks presence/version metadata, not every reflected method.
> After changing Tapioca, RBI, Rubydex, Spoom, or Sorbet reflection tooling, run
> `bin/tapioca gems --all`. The Dependabot workflow makes this choice automatically.

| Path | Ownership |
| --- | --- |
| [`sorbet/config`](../sorbet/config) | Explicit directories scanned by Sorbet |
| [`sorbet/rbi/gems/`](../sorbet/rbi/gems) | Generated gem interfaces |
| [`sorbet/rbi/dsl/`](../sorbet/rbi/dsl) | Generated Rails/custom DSL interfaces |
| [`sorbet/rbi/annotations/`](../sorbet/rbi/annotations) | Community annotations; refresh with `bin/tapioca annotations` |
| [`sorbet/tapioca/compilers/`](../sorbet/tapioca/compilers) | Tested project-specific compiler code |

Do not hand-edit generated RBIs. There are currently no manual shims. The
publisher accepts only gem/DSL RBI paths; annotations and any future shims require
manual review.

## Adoption boundary

Most Ruby files use `typed: false`: Sorbet checks syntax and constant resolution,
but not their method bodies. [`Rebilling::Decision`](../app/services/rebilling/decision.rb)
uses `typed: true`; its factory types the return value while leaving inputs
untyped. A green baseline does not mean the whole application is statically typed.

Promote files gradually, add signatures with behavior tests, and expand the
`Sorbet/TrueSigil` include list in [RuboCop configuration](../.rubocop.yml) as each
file is adopted. `rubocop-sorbet` also checks valid sigils and signature style.

### Runtime checks

Fresh Rails processes configure Sorbet through its API before `Bundler.require`.
The default checked level is `:tests`; development/test enable checks, and
production leaves them disabled. Tools that already loaded Sorbet, including
Tapioca, retain their own policy. See the
[runtime configuration](../config/application.rb) and
[Sorbet's runtime guide](https://sorbet.org/docs/runtime#changing-the-runtime-behavior).

| Operator setting | Effect in a fresh Rails process |
| --- | --- |
| Neither variable set | Default signatures checked in development/test, unchecked in production |
| `SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS=1` | Enable signatures checked at the `:tests` level |
| Flag empty or `0`, `false`, `off`, `no` | Disable test-level checks; case/outer whitespace ignored |
| `SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL=always` | Enable default call checks independently of the test flag |

The app temporarily removes false-like flag values while loading Sorbet, then
restores the supplied value: Sorbet itself treats any presence as enabled.
API defaults create no environment variables, so a development process does not
silently enable checks in a production child. Explicit operator settings remain
inherited. There are no custom error handlers; `.checked(:always)`, inline
assertions, and property validation retain Sorbet's normal behavior.

Signature blocks still execute on first call at every checked level. The
[signature spec](../spec/lib/sorbet_signatures_spec.rb) eagerly loads the app and
runs `T::Utils.run_all_sig_blocks` to catch invalid annotations before deployment.
It cannot prove every call satisfies its signature; production does not report
default call mismatches. The production image excludes development/test gems and
the RBI tree; only `sorbet-runtime` ships for application signatures.

## dry-rb compatibility

| Library | Runtime responsibility | Static boundary |
| --- | --- | --- |
| dry-types | Coercions and constraints | Validator objects are values, not Sorbet class types. Use `::Integer`, `::String`, `T.nilable`, etc. in signatures. |
| dry-monads | `Success` / `Failure` results through `Dry::Monads::Result::Mixin` | Reflected RBIs do not infer payload generics or narrow them from `success?`. |
| dry-initializer / dry-struct | Generated constructors and readers | Tapioca has no bundled compiler for these APIs in the configured toolchain; add reviewed interfaces as coverage expands. |
| dry-validation | Input contracts and service schemas | Successful validation does not become a statically typed record automatically. Translate to a typed boundary object or signature. |

[`DryTypeCatalog`](../lib/dry_type_catalog.rb) is the single `typed: ignore` bridge
around dynamic `Dry.Types`. `Types` and `Rebilling::Types` include the shared
primitives, with fresh, directly owned nested modules. Normal reopening preserves
validators without mutating a sibling namespace:

```ruby
module Types
  module Strict
    Money = Types::String
  end
end
# Types::Strict::Integer still exists; Rebilling::Types::Strict has no Money.
```

Global `Types` extensions do not silently become Rebilling inputs. Rebilling's
types load without Rails. The explicitly required catalog is excluded from
Zeitwerk reloading; restart after editing it. The local
[`DryTypeNamespaces` compiler](../sorbet/tapioca/compilers/dry_type_namespaces.rb)
discovers catalog includers and emits their constants, nested namespaces, and
builder methods without duplicated manual constant lists.

The project does not install archived/unvalidated dry-rb Sorbet adapters. Add
local tested interfaces when adopting more DSL-generated APIs. Current resolved
gem versions live in [`Gemfile.lock`](../Gemfile.lock).
