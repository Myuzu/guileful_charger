# Rebilling

[← README](../README.md#rebilling) · [Algorithm design](rebilling/algorithm-plan.md) ·
[Roadmap and research](rebilling/roadmap.md) · [Operations](operations.md)

The implemented rebilling component is a rules-based **decision planner**. It
accepts snapshots and returns one `Decision`, optionally containing a `Plan` for
the next charge. It does not create payment attempts, call a gateway, or schedule
messages.

> [!IMPORTANT]
> The pure planner is implemented; executing its plans is future integration work.
> `RetryManagerConsumer` currently only logs. A scheduled decision means the
> planner proposed a retry, not that a job or payment was created.

**On this page:** [Objects](#objects-and-responsibilities) · [Decision order](#decision-order) ·
[Default strategy](#default-strategy) · [Amounts and timing](#amounts-and-timing) ·
[Example](#example-plan-one-retry) · [Integration](#integration-contract) · [Tests](#tests)

| Document | Role |
| --- | --- |
| This guide | Current code, API, and integration boundaries |
| [Algorithm design](rebilling/algorithm-plan.md) | Original design rationale, proposed contracts, DSL, and test plan |
| [Roadmap and research](rebilling/roadmap.md) | G1–G25 status, future interfaces, research sources, and priorities |

## Objects and responsibilities

Implementation lives in [`app/services/rebilling/`](../app/services/rebilling).
The similarly named [`lib/rebilling_strategy.rb`](../lib/rebilling_strategy.rb)
is an older unused stub.

| Object | Responsibility |
| --- | --- |
| [`Context`](../app/services/rebilling/context.rb) | Invoice/subscription snapshots, attempt history, methods, and remaining-balance helpers |
| [`Attempt`](../app/services/rebilling/attempt.rb) | Previous attempt state, number, step/method identifiers, and optional failure/version metadata |
| [`PaymentMethodSnapshot`](../app/services/rebilling/payment_method_snapshot.rb) | Method eligibility, primary flag, recent-success metadata, and optional tokenization metadata |
| [`RetryStep`](../app/services/rebilling/retry_step.rb) | Percentage, amount basis, delay/jitter, stable key, and success/failure transitions |
| [`PaymentMethodPolicy`](../app/services/rebilling/payment_method_policy.rb) | Select one eligible method in deterministic order |
| [`FailureClassifier`](../app/services/rebilling/failure_classifier.rb) | Map symbolic reasons/categories to a `FailureClassification` |
| [`DunningStrategy`](../app/services/rebilling/dunning_strategy.rb) | Apply guards, select a step/method, and build a decision |
| [`DecisionOutcome`](../app/services/rebilling/decision_outcome.rb) / [`Decision`](../app/services/rebilling/decision.rb) | Validated status/reason and the result's plan, diagnostics, trace, and notification intent |
| [`Plan`](../app/services/rebilling/plan.rb) | Amount, method, next attempt number, retry window, idempotency key, and strategy/source identifiers |

The strategy uses dry-initializer/types for internal values, and returns an
explicit decision rather than a monadic `Success`/`Failure`. See
[dry-rb and Sorbet boundaries](type-checking.md#dry-rb-compatibility) when adding
signatures. Frozen snapshot containers do not imply deep immutability of every
nested value.

## Decision order

`strategy.next_plan(context, now: ..., trace: false)` evaluates these guards before
building a plan:

1. Stop if the invoice is paid or its remaining balance is zero.
2. Require an `open` or `partially_paid` invoice and an active subscription.
3. Stop while any attempt is `pending`, `scheduled`, or `processing`.
4. Require a terminal attempt; use the one with the highest attempt number.
5. Enforce the strategy's maximum attempt number and reject an unknown step key.
6. Select eligible candidate steps, then a payment method for those candidates.
7. Calculate the capped amount, retry window, and stable plan identifiers.

| Decision status | Meaning |
| --- | --- |
| `scheduled` | A plan is available |
| `invoice_paid` | No remaining collection is needed |
| `subscription_inactive` | The subscription cannot be billed |
| `in_flight_attempt_exists` | Wait for existing work to finish |
| `not_retryable` | Invoice/history/failure is unsuitable, including an unknown step key |
| `no_eligible_payment_method` | The current candidate selection found no usable method |
| `exhausted` | Maximum attempts reached or the step chain ended/stopped |

Inspect `reason` and `diagnostics` for the specific branch. An initial completed
attempt with an unreconciled balance stops as `:not_retryable`; the planner does
not infer or apply invoice settlement.

### Step and payment-method selection

An initial failed attempt enters the first step only if its failure classification
is business-retryable. By default, only `:soft_decline` qualifies;
`insufficient_funds` maps to that category. Technical failures and customer-action
reasons do not become business rebilling attempts.

Each step supports `:repeat`, `:next`, and `:stop` transitions. After a failed retry,
the default policy considers another eligible method for the current step before
its failure transition. After success it follows the success transition, preferring
the successful method when repeating the same step. Candidate selection does not
scan every later step arbitrarily.

Methods are ordered by primary flag, most recent success, then ID. Inactive and
hard-declined methods are skipped; a method that already failed a step is excluded
for that step by default. The planner returns one plan at a time.

## Default strategy

`Rebilling::DunningStrategy.default` defines the following ordered steps:

| Step | Percentage | Delay | On success | On failure |
| --- | --- | --- | --- | --- |
| 1 | 75% | 1 day | Repeat | Next |
| 2 | 50% | 1 day | Repeat | Next |
| 3 | 25% | 5 minutes | Next | Next |
| 4 | 25% | 1 minute | Repeat | Next |
| 5 | 15% | 5 minutes | Repeat | Next |
| 6 | 10% | 5 minutes | Repeat | Next |
| 7 | 5% | 5 minutes | Repeat | Stop |

The method waterfall is considered before a failed step's transition. This is not
an unconditional percentage ladder: successful chunks can repeat until the
balance is paid, the step changes, or a guard stops recovery.

The default maximum attempt number is **12**, including the initial full charge:
attempt 1 is initial, and attempts 2–12 are potential retries. The guard uses the
latest terminal attempt number, not the size of the supplied history. It does not
enforce payment-network-specific rolling windows.

## Amounts and timing

| Rule | Current behavior |
| --- | --- |
| `:invoice_total` basis | Default; compute a stable chunk of the original total |
| `:remaining_balance` basis | Compute a fraction of the current balance; steps may mix bases |
| Rounding / cap | Round the calculated amount up to cents, then cap it at the remaining balance |
| Step key | Generated from percentage, basis, and normalized delay; explicit keys are allowed and duplicates are rejected |
| Retry window | `now + delay`, plus configured minimum/maximum jitter |
| Jitter | Deterministic CRC32 based on invoice ID, next attempt number, and step key; defaults to `0..0` |
| Plan identity | Invoice ID, source attempt ID, strategy version, selected step key, and payment method ID |

For a 1,200-cent invoice, 25% of the total is 300 cents. If only 180 cents remain,
the proposed amount is 180 cents. Choosing the remaining-balance basis changes
the fraction being calculated, but retains the same cap.

Supply the **same `now`**, snapshots, and configuration for repeatable decisions.
The default `Time.current` changes between calls. A version number travels with
the plan, but there is no historical strategy registry yet; changing a generated
step's delay changes its key.

## Example: plan one retry

Run this in a Rails console, or as a Rails runner script. It uses only snapshot
objects and does not persist or execute the resulting plan:

```ruby
now = Time.utc(2026, 10, 29, 12)
attempt = Rebilling::Attempt.new(
  id: "attempt-1",
  attempt_number: 1,
  status: :failed,
  amount_attempted_cents: 1200,
  failure_reason: :insufficient_funds,
  payment_method_id: "method-primary"
)
method = Rebilling::PaymentMethodSnapshot.new(
  id: "method-primary", primary: true
)
context = Rebilling::Context.new(
  invoice_id: "invoice-1",
  invoice_status: :open,
  invoice_total_cents: 1200,
  amount_paid_cents: 0,
  subscription_status: :active,
  attempts: [attempt],
  payment_methods: [method]
)
decision = Rebilling::DunningStrategy.default.next_plan(
  context, now: now, trace: true
)

decision.status               # => :scheduled
decision.plan.amount_cents    # => 900
decision.plan.attempt_number  # => 2
decision.plan.retry_at        # => 2026-10-30 12:00:00 UTC
decision.plan.idempotency_key # => rebill:invoice-1:attempt-1:v1:charge_75pct_invoice_total_after_86400s:method-primary
```

`trace: true` records candidate selection, method selection, amount calculation,
and terminal outcomes where applicable. It is not a complete log of every guard.
The default recorder is called once per decision but stores nothing.

## Integration contract

The next execution slice must connect the planner to persisted billing state:

- Build a fresh context after reconciling successful payments. Current
  `Context#to_h` omits attempts/methods and is not a full replay snapshot.
- Lock/recheck invoice and subscription state before persisting a proposed retry;
  enforce its idempotency key with a database uniqueness constraint.
- Preserve the source attempt, strategy version, step, and method identifiers.
  Map `Plan#retry_strategy` explicitly: the planner's amount bases differ from
  the current `PaymentAttempt` enum (`initial`, `remaining_balance`).
- Enqueue the persisted attempt through the outbox, and consume its retry window
  in a scheduler. Existing RabbitMQ TTL queues do not perform this integration.
- Reconcile outcomes, then request the next decision. Apply exhaustion and
  notification policies in the execution layer.

`DecisionRecorder`, `ScoringPolicy`, and `PostExhaustionPolicy` are interfaces or
no-op defaults. Scoring is not consulted, notification intent remains `:none`,
and returning `:pause_subscription` does not pause anything. See the
[G1–G25 status table](rebilling/roadmap.md#current-status) before treating a proposed
interface as implemented behavior.

## Tests

The planner does not query Active Record, but the checked-in specs currently use
`rails_helper`. Run them with the project's prepared test database:

```bash
make test RSPEC_ARGS="spec/services/rebilling"
```

The [spec directory](../spec/services/rebilling) covers amounts, transitions,
payment-method selection, classification, diagnostics, timing, and fixed-context
invariants. Generated property tests, persisted replay fixtures, and a runtime
strategy visualizer remain [roadmap items](rebilling/roadmap.md#testing-and-debugging).
