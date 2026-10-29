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
| [`sorbet/rbi/shims/`](../sorbet/rbi/shims) | Reviewed interfaces for dynamic rebilling values and Money precision |
| [`sorbet/tapioca/compilers/`](../sorbet/tapioca/compilers) | Tested project-specific compiler code |

Do not hand-edit generated RBIs. Keep manual contracts in `shims`, backed by
runtime and isolated positive/negative static tests. The publisher accepts only
gem/DSL RBI paths; annotations and shims require manual review.

## Adoption boundary

Use **`typed: strict`** for every new or newly adopted application Ruby file and
handwritten RBI. `typed: true` is a legacy migration level, not the adoption target.
The original rebilling values have been promoted to strict in
[#299](https://github.com/Myuzu/guileful_charger/issues/299); all adopted classes
listed below now use strict.
Generated interfaces retain their generator's sigils. Most existing Ruby files
still use `typed: false`: Sorbet checks syntax and constants, but not method bodies.

| Level | Guarantee |
| --- | --- |
| `true` | Checks method bodies while allowing missing signatures and implicit untyped values |
| `strict` | Also requires signatures and types for fields/constants; safe literal inference is supported and explicit `T.untyped` is still permitted |

These are [static checking levels](https://sorbet.org/docs/static). Neither changes
the production runtime policy described below. Use accurate contracts and opaque
forwarding types rather than adding untyped annotations merely to satisfy strict.

| Class | Current level | Checked contract |
| --- | --- | --- |
| [`FailureClassifier`](../app/services/rebilling/failure_classifier.rb) | **`strict`** | Attempt/reason inputs and classification output; implements the classifier contract |
| [`FailureClassifierContract`](../app/services/rebilling/failure_classifier_contract.rb) | **`strict`** | Injectable classifier interface: Attempt to FailureClassification |
| [`FailureClassification`](../app/services/rebilling/failure_classification.rb) | **`strict`** | Symbol category, optional network recommendation, boolean flags |
| [`Plan`](../app/services/rebilling/plan.rb) | **`strict`** | Integer amounts/counters, symbol strategy keys, string idempotency key, Time/TimeWithZone timestamps |
| [`Decision`](../app/services/rebilling/decision.rb) | **`strict`** | Outcome/optional Plan inputs, inherited factory results, diagnostics/trace containers, boolean predicates |
| [`DecisionOutcome`](../app/services/rebilling/decision_outcome.rb) | **`strict`** | Required string/symbol status and reason inputs, normalized symbol readers, inherited constructor return type |
| [`RetryStep`](../app/services/rebilling/retry_step.rb) | **`strict`** | Opaque constructor forwarding, normalized key, bounded integer jitter, amount calculations and retry windows |
| [`Attempt`](../app/services/rebilling/attempt.rb) | **`strict`** | Integer amount/attempt readers, optional failure/step symbols, status predicates |
| [`Context`](../app/services/rebilling/context.rb) | **`strict`** | Typed frozen collection fields, integer balances, history queries and observability snapshot |
| [`PaymentMethodSnapshot`](../app/services/rebilling/payment_method_snapshot.rb) | **`strict`** | Boolean primary flag, symbol status/kind fields, eligibility predicates |
| [`PaymentMethodPolicy`](../app/services/rebilling/payment_method_policy.rb) | **`strict`** | Constructor/defaults, boolean flags, typed candidate filtering/sorting, optional selected snapshot |
| [`PaymentMethodPolicyContract`](../app/services/rebilling/payment_method_policy_contract.rb) | **`strict`** | Injectable method selection and per-step waterfall flag |
| [`DunningStrategy`](../app/services/rebilling/dunning_strategy.rb) and its Builder | **`strict`** | Constructor/readers, factories and builder receiver, optional planner results, transitions, diagnostics and trace |
| [`DecisionRecorder`](../app/services/rebilling/decision_recorder.rb) | **`strict`** | Both no-op hooks accept ignored values and return nil |
| [`DecisionRecorderContract`](../app/services/rebilling/decision_recorder_contract.rb) | **`strict`** | Active planner hook: Context/Decision inputs with an ignored result |
| [`ScoringPolicy`](../app/services/rebilling/scoring_policy.rb) | **`strict`** | Ignored context, RetryStep enumerable, Symbol-to-nil placeholder score map |
| [`PostExhaustionPolicy`](../app/services/rebilling/post_exhaustion_policy.rb) | **`strict`** | Opaque ignored inputs, Symbol action (`:pause_subscription` today), no effects |

The reviewed RBIs describe dynamic `Data.define` members and the dry-initializer
readers these methods consume. Typed Data callers use keyword `.new`/`[]` and
partial keyword `.with` updates. Ruby's positional constructors, equality,
shallow freezing, and `with` behavior remain available at runtime; the interfaces
do not add Data member validation. Identifier fields remain `Object` because
snapshot IDs are unconstrained, including nil and integers. Diagnostic/trace
values also remain heterogeneous; their containers have symbol keys.

Reviewed constructors, Data `[]`, and `Decision.from_outcome` preserve the concrete
subclass with [`T.attached_class`](https://sorbet.org/docs/attached-class). Data
`with` updates use [`T.self_type`](https://sorbet.org/docs/self-type) to preserve the
receiver's type. Runtime and isolated static probes cover inherited construction
and updates; the interfaces retain all existing keyword input checks.

RetryStep's constructor accepts broad inputs for dry-types to coerce and validate;
its output readers expose normalized Integer/Float, Symbol, and integer Range
types. Typed snapshot constructors accept Integer or integer strings for monetary
and counter inputs, so a possible fractional Money value needs an explicit policy
before crossing the boundary. Other coerced fields retain broad inputs.
Uncoerced timestamps use nilable Time/TimeWithZone contracts, timezone is a
nilable String, and Context collections contain the corresponding snapshots.
Those are static caller contracts; existing dry coercions remain unchanged and
dry-initializer does not gain runtime element or timestamp validation. Context
freezes supplied arrays and metadata in place, without deep freezing. Metadata
permits heterogeneous keys and values.

Attempt, Context, PaymentMethodSnapshot, and RetryStep keep opaque `T.anything`
initializer forwarding, with reviewed `.new` interfaces for typed callers. Their
strict annotations preserve dry coercions and freezing. RetryStep's key field
accounts for dry-initializer's transient nil/module sentinel; its public reader
remains a normalized Symbol. Jitter normalization produces bounded integer ranges,
so the bound accessors return integers directly without redundant nil assertions.

DecisionOutcome's reviewed constructor contract requires both keyword options
and accepts strings or symbols. dry-types still owns allowed status/reason values;
the static types describe their shape rather than their enum membership. The
runtime constructor retains its forwarding, custom symbol coercion, required-option
errors, and freezing. Its strict initializer signature uses `T.anything` for opaque
forwarded values; the reviewed `.new` contract checks typed caller inputs. The
constructor returns `T.attached_class`, preserving subclass inference. This follows
[Sorbet's RBI guidance](https://sorbet.org/docs/rbi)
for dynamic methods and [dry-initializer's coercion model](https://dry-rb.org/gems/dry-initializer/main/type-constraints/).
A green baseline does not mean the whole application is statically typed.

Promote files to strict with behavior tests and expand `Sorbet/StrictSigil` in
[RuboCop configuration](../.rubocop.yml). The legacy `Sorbet/TrueSigil` include list
has been removed after this promotion. `rubocop-sorbet` also checks valid sigils and
signature style.

### Classifier injection

PaymentMethodPolicy accepts `FailureClassifierContract` for typed injection.
Implementations include the interface and override `classify_attempt(Attempt)`
with a `FailureClassification` result, following [Sorbet's interface model](https://sorbet.org/docs/abstract).
The default FailureClassifier implements the same contract; custom implementations
can supply different classification logic. Raw constructor forwarding preserves
existing runtime duck typing and dry option validation.

Selection accepts Context/RetryStep snapshots and returns a nilable
PaymentMethodSnapshot. Preferred IDs retain the snapshots' `Object` contract,
including integer and nil identifiers. The policy preserves active/hard-decline
filtering, per-step exclusions, primary/recent-success/ID ordering, and defaults.

### Planner and builder DSL

DunningStrategy's reviewed constructor accepts RetryStep arrays, integer/string
version and attempt-limit options, symbol/string category arrays, and typed
collaborators. Normalized readers expose integer counters and symbol categories.
`next_plan` takes a Context, a Time/TimeWithZone clock value, and a boolean trace
flag, and returns a Decision. Helpers model missing attempts, steps, and selected
methods explicitly. Diagnostics and trace entries remain open symbol-keyed hashes;
the types do not impose a closed observability schema.

The Builder block has both a typed `self` and an optional caller-declared Builder
argument, using [Sorbet's bound proc signatures](https://sorbet.org/docs/procs).
`step` retains its Array-of-RetryStep return value. `.build` and `.default` retain
subclass return types and dry-initializer's subclass option defaults.

> [!NOTE]
> `.build(**options)` and `step(percentage, **options)` forward opaque options to
> dry-initializer. Recognized options retain coercion, constraint, and required-option
> checks, including the missing-delay error; unknown keyword names are silently
> ignored. Narrow `T.unsafe` bridges cover those dynamic keyword
> hashes and the core RBI's missing `instance_eval` block argument. The reviewed
> `.new` interface checks constructor options statically; the DSL still checks the
> builder receiver, available methods, and result types.

Typed custom selectors include PaymentMethodPolicyContract and implement `select`
and `exhaust_methods_per_step?`. The existing `select` name also shadows
`Kernel#select`; its override needs `allow_incompatible: true` for that unrelated
IO signature. Typed recorders include DecisionRecorderContract and implement
`record(Context, Decision)`; the planner ignores the return value. The default
recorder's `record` and reserved `record_shadows` accept arbitrary ignored values
and return nil. Existing runtime duck-typed collaborators and RSpec spies remain
usable. Scoring is an opaque reserved option and is never consulted; these
contracts add no scoring, shadow execution, persistence, or gateway integration.

ScoringPolicy's reserved `score` hook accepts an opaque ignored context and a
RetryStep enumerable, returning `T::Hash[Symbol, NilClass]`. Arrays and enumerators
are accepted. Empty input yields an empty map; repeated step keys share one nil
entry. Each call returns a fresh mutable
map. The planner still does not consult this hook. Static checks reject passing
this nil-valued map to a numeric-score consumer.

PostExhaustionPolicy's `handle` hook accepts two opaque ignored inputs
(`T.anything`) and returns a Symbol. Its current `:pause_subscription` result is a
placeholder action value; the hook does not pause subscriptions, write records,
or dispatch notifications. Nil invoices and arbitrary placeholder reasons remain
accepted. These input types do not imply a billing integration.

### Money and integer minor units

Keep the gem contract distinct from the application's stored amounts:

| Value | Sorbet type | Meaning |
| --- | --- | --- |
| `Money#cents`, `Money#fractional` | `T.any(Integer, BigDecimal)` | Integer normally; BigDecimal when `Money.default_infinite_precision` is enabled, even for whole subunits |
| Rebilling `*_cents`, `Plan#amount_cents`, `AmountCalculation` members | `Integer` | Whole minor units, matching the database columns and the Context dry-types contract |
| RetryStep percentage | `T.any(Integer, Float)` | A percentage, not a monetary amount; the existing calculation rounds up and caps at the remaining integer balance |

The [locked Money source](https://github.com/RubyMoney/money/blob/v7.0.2/lib/money/money.rb)
defines `cents` as a synonym of `fractional` and selects the return class using the
precision setting. The app sets UAH and half-even rounding in its
[initializer](../config/initializers/money.rb), and leaves infinite precision at
the gem's false default. The manual Money RBI retains the full gem contract so a
later precision change cannot silently make an Integer-only annotation wrong.

At a future Money-to-planner boundary, prefer the stored integer column; otherwise
check precision and apply an explicit rounding/rejection policy before converting.
Do not use `T.cast(..., Integer)` or an unchecked `.to_i` to hide fractional
subunits. [MoneyRails' monetized readers](https://github.com/RubyMoney/money-rails/blob/v3.0.0/lib/money-rails/active_record/monetizable.rb)
return Money backed by the separate numeric column; those are different interfaces.

Despite the name, `cents` means the currency's **minor units**, not universally
hundredths. For example, one UAH is 100 subunits, one JPY is 1, and one KWD is
1,000. Use the currency's `subunit_to_unit` for major-unit conversions, as in the
[Money currency documentation](https://rubymoney.github.io/money/#currency).
Money does not make a bare Integer carry currency information; the current
rebilling snapshot has no currency field, so currency conversion belongs outside
this typed core.

### Runtime checks

Rails processes configure Sorbet through its API before framework/gem loading.
The default checked level is `:tests`; development/test enable checks, and
production leaves them disabled. Preloaded runtimes are configured too, provided
their signatures have not locked the default. See the measured
[runtime policy](../lib/sorbet_runtime_configuration.rb), its
[application entry point](../config/application.rb), and
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

If a preloader already evaluated signatures, Sorbet's public API cannot reset
their default. Production then stops boot with `PolicyError`, rather than serving
requests under an unexpected policy. Configure `SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL`
before preloading Sorbet, or load application configuration before evaluating
signatures. A false-like test-checking flag must also be removed before preloading:
Sorbet has already enabled it by presence and has no public disable API. Local
tools such as Tapioca warn and retain their preconfigured policy when it is locked.

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
types load without Rails. Including the catalog again preserves directly owned
nested modules and application extensions without constant redefinition warnings.
The explicitly required catalog is excluded from
Zeitwerk reloading; restart after editing it. The local
[`DryTypeNamespaces` compiler](../sorbet/tapioca/compilers/dry_type_namespaces.rb)
discovers catalog includers and emits their constants, nested namespaces, and
builder methods without duplicated manual constant lists.

The project does not install archived/unvalidated dry-rb Sorbet adapters. Add
local tested interfaces when adopting more DSL-generated APIs. Current resolved
gem versions live in [`Gemfile.lock`](../Gemfile.lock).
