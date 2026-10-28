# Rebilling algorithm design

[← Rebilling guide](../rebilling.md) · [Roadmap and research](roadmap.md)

> [!NOTE]
> This is the original design proposal from `REBILLING_ALG.md`. The pure planner
> is now implemented. Proposed fields, pseudocode, and the test plan below explain
> its design; the [current implementation guide](../rebilling.md) describes the
> actual API and integration boundaries.

**Contents:** [Goal](#goal) · [Original problem](#original-problem-statement) ·
[Design principles](#design-principles) · [Core concepts](#core-concepts) ·
[Algorithm](#algorithm) · [Default strategy](#example-default-strategy) ·
[Guardrails](#guardrails) · [Test plan](#test-plan) ·
[Persistence](#future-persistence-implications)

## Goal

Design a flexible, deterministic rebilling strategy for partial subscription payment recovery.

The strategy must support the current desired behavior, such as percentage-based partial charges, while staying extensible for:

- different percentage ladders;
- repeated successful partial-charge amounts;
- fallback to smaller amounts after a previously successful amount fails;
- the same percentage with different retry delays;
- all available customer payment methods;
- clear debugging and testability.

This document is a design plan only. It intentionally does not prescribe database migrations, consumers, or scheduler implementation details beyond the strategy-facing data they will eventually need.

## Original problem statement

Before the pure planner was implemented, the billing flow had these missing pieces:

- no retry amount calculation;
- no retry scheduling workflow;
- no implementation of the 75% / 50% / 25% partial-charge ladder;
- no maximum retry enforcement beyond configuration placeholders;
- no invoice/subscription status updates after retry exhaustion;
- no strategy for trying all available payment methods.

A simple fixed ladder is not enough. For example, after failing to charge 75% and 50%, a 25% charge may succeed. We may then want to keep charging 25% until it fails, and only then fall back to 15%, 10%, 5%, etc.

Example target flow:

```text
100% initial attempt -> insufficient_funds
75% retry           -> insufficient_funds
50% retry           -> insufficient_funds
25% retry, 5m delay -> success
25% retry, 1m delay -> success
25% retry, 1m delay -> insufficient_funds
15% retry, 5m delay -> success
```

This requires a small deterministic policy engine, not just `attempt_number -> percentage` mapping.

## Design Principles

1. **Deterministic and explainable**
   - Given the same invoice/payment history and strategy config, the next rebilling plan should always be the same.

2. **Pure strategy logic**
   - The strategy should not query ActiveRecord directly.
   - It should operate on immutable snapshots/context objects.

3. **Easy to test**
   - Unit tests for strategy math and transitions should not require the database, factories, RabbitMQ, or payment gateway mocks.

4. **Easy to debug**
   - The strategy should return a structured decision with diagnostics instead of `nil` or opaque booleans.

5. **Configurable, but not overengineered**
   - Support ordered retry steps, transitions, delays, payment-method selection, and guardrails.
   - Avoid ML/smart retry timing, external gateway recommendations, or full rule-engine complexity for now.

6. **Safe with payment methods**
   - The strategy should return one next plan at a time.
   - It should not suggest parallel attempts against multiple payment methods.

## Industry Patterns to Borrow

### Soft vs Hard Declines

Retry behavior should eventually depend on normalized failure categories rather than raw gateway codes.

Typical categories:

| Category | Examples | Strategy |
| --- | --- | --- |
| Soft decline | insufficient funds, generic do-not-honor | Retry later, maybe lower amount or different method |
| Hard decline | stolen card, invalid card number | Do not retry same method |
| Customer action required | authentication required, expired card | Stop and ask customer to update/authenticate |
| Technical failure | network error, processor unavailable | Broker/system retry, not business rebilling |

For the first strategy version, default business-retryable failure can be limited to:

```ruby
:insufficient_funds
```

System errors should remain broker-level retry concerns, not business rebilling attempts.

### Payment Method Waterfall

When multiple payment methods exist, the strategy should be able to try all eligible methods deterministically.

Recommended default policy:

```text
For the selected amount step:
  try the preferred/primary method first;
  then try backup methods in policy order;
if all eligible methods fail for that step:
  move to the next lower amount step.
```

This is an **amount-first, method-waterfall** approach.

Pros:

- maximizes recovery of larger amounts;
- gives backup payment methods a chance before lowering the charge;
- remains predictable and easy to audit.

### Sticky Success + Fallback

Recommended amount behavior:

```text
Failure at a step -> move to next lower step.
Success at a step with balance remaining -> follow that step's success transition.
```

Most steps will use:

```text
on_success: repeat
on_failure: next
```

But some steps may use:

```text
on_success: next
```

This supports flows where the first successful 25% charge with a longer delay transitions into a faster 25% retry step.

## First Implementation Slice

The first implementation should build the pure, database-independent decision engine only:

- `Rebilling::DunningStrategy` with `version`, ordered steps, max-attempt guardrail, trace mode, and deterministic decision output.
- `Rebilling::RetryStep` with generated keys from percentage + basis + delay, amount calculation, retry windows, and deterministic jitter.
- `Rebilling::PaymentMethodPolicy` with primary-first ordering, classifier-backed hard-decline skipping, and method waterfall per step.
- Snapshot/value objects: `Context`, `Attempt`, `PaymentMethodSnapshot`, `Plan`, `Decision`, and `FailureClassification`.
- Minimal interfaces/no-op defaults: `FailureClassifier`, `DecisionRecorder`, `ScoringPolicy`, and `PostExhaustionPolicy`.
- Lightweight dry-rb usage through `Dry::Initializer` and a small `Rebilling::Types` module for coercion/validation of internal value objects.
- A compact strategy DSL for readable strategy definitions.

This slice must not create payment attempts, update invoices, enqueue messages, or add persistence. Those belong to the next integration slice after the strategy behavior is covered by pure unit tests.

Example DSL:

```ruby
Rebilling::DunningStrategy.build(version: 1, max_attempts: 12) do
  step 75, delay: 1.day
  step 50, delay: 1.day
  step 25, delay: 5.minutes, on_success: :next
  step 25, delay: 1.minute
  step 15, delay: 5.minutes
  step 10, delay: 5.minutes
  step 5, delay: 5.minutes, on_failure: :stop
end
```

## Core Concepts

### Rebilling::RetryStep

A retry step represents an amount/timing state.

Responsibilities:

- calculate amount to attempt;
- identify itself with a stable key;
- define delay before the retry;
- define transition behavior after success/failure.

Suggested fields:

```ruby
percentage
basis
raw_delay / delay
key
on_success
on_failure
```

Retryability belongs at strategy/failure-classifier level by default. A per-step override can be added later if a real use case appears.

Default values:

```ruby
basis: :invoice_total
on_success: :repeat
on_failure: :next
```

Supported bases:

```ruby
:invoice_total
:remaining_balance
```

Default should be:

```ruby
:invoice_total
```

Reason: stable chunk sizes are easier to reason about.

Example with invoice total 1200 cents:

```text
25% of invoice total = 300 cents
```

This allows:

```text
300 + 300 + 300 + 300
```

instead of shrinking attempts:

```text
300 + 225 + 169 + 127 + ...
```

The amount should always be capped by current remaining balance:

```ruby
amount_cents = [calculated_amount_cents, context.amount_remaining_cents].min
```

#### Retry Step Key

The key must identify the behavior that matters for history and transition decisions.

Percentage alone is insufficient because this is valid:

```ruby
RetryStep.new(percentage: 25, delay: 5.minutes)
RetryStep.new(percentage: 25, delay: 1.minute)
```

Therefore, generated keys should include:

```text
percentage + basis + normalized delay
```

Examples:

```text
charge_25pct_invoice_total_after_300s
charge_25pct_invoice_total_after_60s
charge_15pct_invoice_total_after_300s
```

Explicit keys should remain optional for advanced cases.

If two steps generate the same key, strategy initialization should raise a duplicate key error. If the business truly needs duplicate amount/basis/delay steps with different transitions, those steps should provide explicit keys.

### Rebilling::PaymentMethodPolicy

A payment-method policy selects which eligible payment method should be tried for a selected retry step.

Responsibilities:

- order payment methods;
- skip hard-declined or inactive methods;
- avoid retrying the same method for the same step after an ineligible failure;
- choose one next method, not a batch.

Suggested configuration:

```ruby
order: :primary_then_recent_success
exhaust_methods_per_step: true
retry_same_method_after_soft_decline: false
skip_hard_declined_methods: true
```

Default recommendation:

```ruby
exhaust_methods_per_step: true
skip_hard_declined_methods: true
retry_same_method_after_soft_decline: false
```

Meaning:

```text
Try eligible backup methods for the current amount step before falling back to a lower amount.
```

### Rebilling::DunningStrategy

The dunning strategy coordinates retry steps and payment-method policy. The name is intentionally specific: this is the asynchronous, scheduled dunning/rebilling strategy, not a future synchronous in-authorization adaptive-acceptance strategy.

It should return a `Rebilling::Decision`, not `nil`.

Primary API:

```ruby
decision = strategy.next_plan(context, now: Time.current)
```

It should not create database records or enqueue messages.

### Rebilling::Context

A pure snapshot of invoice/subscription/payment state.

Suggested fields:

```ruby
invoice_id
invoice_status
invoice_total_cents
amount_paid_cents
subscription_status
attempts
payment_methods
```

Useful helpers:

```ruby
amount_remaining_cents
paid?
retryable_invoice?
active_subscription?
in_flight_attempt?
latest_terminal_attempt
max_attempts_reached?
```

### Rebilling::Attempt

A pure snapshot of a previous payment attempt.

Suggested fields:

```ruby
id
attempt_number
status
amount_attempted_cents
failure_reason
failure_category
retry_step_key
payment_method_id
created_at
completed_at
failed_at
```

Eventually, the database should persist at least:

```text
payment_attempts.retry_step_key
payment_attempts.payment_method_id
payment_attempts.failure_category
payment_attempts.failure_code
```

`retry_step_key` is important. Without it, the strategy would need to infer the step from amount, which becomes fragile once order, delay, basis, or custom percentages are configurable.

### Rebilling::PaymentMethodSnapshot

A pure snapshot of a customer payment method.

Suggested fields:

```ruby
id
status
primary
kind
last_successful_at
last_failed_at
failure_category
```

Potential statuses:

```ruby
:active
:expired
:invalid
:requires_action
:disabled
```

### Rebilling::Plan

The next retry attempt proposed by the strategy.

Suggested fields:

```ruby
step_key
payment_method_id
attempt_number
amount_cents
retry_at
retry_strategy
idempotency_key
strategy_version
source_attempt_id
earliest_retry_at
latest_retry_at
```

`retry_strategy` should reflect the selected step basis (`:invoice_total` or `:remaining_balance`) in the pure strategy plan. If the persistence enum uses different values, the integration layer must map this explicitly rather than silently storing the wrong strategy.

Example:

```ruby
now = Time.current
Rebilling::Plan.new(
  step_key: :charge_25pct_invoice_total_after_60s,
  payment_method_id: "pm_backup_1",
  attempt_number: 7,
  amount_cents: 300,
  retry_at: now + 1.minute,
  earliest_retry_at: now + 1.minute,
  latest_retry_at: now + 3.minutes,
  retry_strategy: :invoice_total,
  idempotency_key: "rebill:inv_123:pa_122:v1:charge_25pct_invoice_total_after_60s:pm_backup_1",
  strategy_version: 1,
  source_attempt_id: "pa_122"
)
```

### Rebilling::DecisionOutcome

Internal typed status/reason value object used by strategy helper methods instead of raw positional tuples such as `[:not_retryable, :non_retryable_failure_reason]`.

Suggested fields:

```ruby
status
reason
```

Both fields should be validated through dry-rb types so invalid statuses/reasons fail at construction time.

### Rebilling::Decision

Structured strategy result.

Suggested fields:

```ruby
status
reason
plan
diagnostics
```

Potential statuses:

```ruby
:scheduled
:exhausted
:not_retryable
:invoice_paid
:subscription_inactive
:in_flight_attempt_exists
:no_eligible_payment_method
```

Potential reasons:

```ruby
:initial_attempt_failed
:last_step_failed
:last_step_succeeded
:no_next_step
:max_attempts_reached
:invoice_already_paid
:invoice_not_retryable
:subscription_not_active
:non_retryable_failure_reason
:no_terminal_attempt
:no_eligible_payment_method
```

Diagnostics should be log-friendly.

Example:

```ruby
{
  invoice_id: "inv_123",
  invoice_total_cents: 1200,
  amount_paid_cents: 300,
  amount_remaining_cents: 900,
  last_attempt_id: "pa_123",
  last_attempt_number: 6,
  last_attempt_status: :failed,
  last_failure_category: :soft_decline,
  last_failure_reason: :insufficient_funds,
  last_retry_step_key: :charge_25pct_invoice_total_after_60s,
  selected_step_key: :charge_15pct_invoice_total_after_300s,
  selected_percentage: 15,
  selected_basis: :invoice_total,
  selected_payment_method_id: "pm_backup_1",
  calculated_amount_cents: 180,
  capped_amount_cents: 180,
  reason: :last_step_failed
}
```

## Algorithm

The following is design pseudocode, not a callable implementation. In the current
planner, max attempts are checked against the latest terminal attempt; candidate
selection considers the current/transition steps rather than scanning every later
step. Unknown step keys stop safely, and an unavailable method can return
`:no_eligible_payment_method`. See the [implemented decision order](../rebilling.md#decision-order).

### High-Level Flow

```ruby
def next_plan(context, now: Time.current)
  return invoice_paid_decision(context) if context.amount_remaining_cents <= 0
  return not_retryable_decision(context, :invoice_not_retryable) unless context.retryable_invoice?
  return subscription_inactive_decision(context) unless context.active_subscription?
  return in_flight_decision(context) if context.in_flight_attempt?
  return exhausted_decision(context, :max_attempts_reached) if context.max_attempts_reached?

  last_attempt = context.latest_terminal_attempt
  return not_retryable_decision(context, :no_terminal_attempt) unless last_attempt

  selected_step = select_step(context, last_attempt)
  return exhausted_decision(context, :no_next_step) unless selected_step

  selected_payment_method = payment_method_policy.select(context, selected_step)

  while selected_step && selected_payment_method.nil?
    selected_step = next_step_after(selected_step)
    selected_payment_method = payment_method_policy.select(context, selected_step) if selected_step
  end

  return exhausted_decision(context, :no_eligible_payment_method) unless selected_step && selected_payment_method

  amount_cents = selected_step.amount_for(context)
  scheduled_decision(context, selected_step, selected_payment_method, amount_cents, now)
end
```

### Step Selection

```ruby
def select_step(context, last_attempt)
  if last_attempt.retry_step_key.nil?
    return steps.first if retryable_failure?(last_attempt)
    return nil
  end

  current_step = step_by_key.fetch(last_attempt.retry_step_key)

  transition =
    if last_attempt.completed?
      current_step.on_success
    elsif retryable_failure?(last_attempt)
      current_step.on_failure
    else
      :stop
    end

  resolve_transition(current_step, transition)
end
```

### Transition Resolution

Start with these transitions:

```ruby
:repeat
:next
:stop
```

Resolution:

```ruby
case transition
when :repeat
  current_step
when :next
  next_step_after(current_step)
when :stop
  nil
end
```

Later, this can be extended to explicit transition targets:

```ruby
on_failure: :charge_5pct_invoice_total_after_300s
```

Do not add explicit target transitions until needed.

## Example Default Strategy

A default strategy could start as:

```ruby
Rebilling::DunningStrategy.new(
  steps: [
    Rebilling::RetryStep.new(
      percentage: 75,
      delay: 1.day,
      on_success: :repeat,
      on_failure: :next
    ),
    Rebilling::RetryStep.new(
      percentage: 50,
      delay: 1.day,
      on_success: :repeat,
      on_failure: :next
    ),
    Rebilling::RetryStep.new(
      percentage: 25,
      delay: 5.minutes,
      on_success: :next,
      on_failure: :next
    ),
    Rebilling::RetryStep.new(
      percentage: 25,
      delay: 1.minute,
      on_success: :repeat,
      on_failure: :next
    ),
    Rebilling::RetryStep.new(
      percentage: 15,
      delay: 5.minutes,
      on_success: :repeat,
      on_failure: :next
    ),
    Rebilling::RetryStep.new(
      percentage: 10,
      delay: 5.minutes,
      on_success: :repeat,
      on_failure: :next
    ),
    Rebilling::RetryStep.new(
      percentage: 5,
      delay: 5.minutes,
      on_success: :repeat,
      on_failure: :stop
    )
  ],
  max_attempts: 12,
  payment_method_policy: Rebilling::PaymentMethodPolicy.default
)
```

This supports:

```text
75 fails -> 50
50 fails -> 25 after 5m
25 after 5m succeeds -> 25 after 1m
25 after 1m succeeds -> 25 after 1m again
25 after 1m fails -> another eligible method for same step, or 15 after 5m
15 after 5m succeeds -> 15 after 5m again
15 after 5m fails -> 10 after 5m
```

Whether the strategy tries another payment method before falling to 15% is controlled by `PaymentMethodPolicy`.

## Guardrails

The strategy should include guardrails to avoid infinite or excessive retrying.

Start with:

```ruby
max_attempts
```

Where `attempt_number` includes the initial full payment attempt.

Example:

```text
attempt 1 = initial full charge
attempts 2..12 = retries
```

Later guardrails may include:

```ruby
max_attempts_per_payment_method
max_total_duration
min_amount_cents
max_attempts_per_failure_category
```

Do not overreach in the first implementation.

## Dry-rb Recommendation

The project already uses dry-rb, but this strategy should stay lightweight.

### Use dry-rb where useful

Good candidates for `Dry::Struct` or lightweight type validation:

- `RetryStep`
- `PaymentMethodPolicy` config
- `Strategy` config

Pros:

- catches invalid config early;
- validates percentage bounds and enum values;
- documents allowed values clearly.

### Avoid dry-validation

Do not use `dry-validation` for strategy internals.

Reason:

- this is internal strategy/config data, not external payload input;
- validation rules are simple;
- `Dry::Struct` or explicit initializer checks are enough.

### Avoid dry-monads in the strategy

Do not return `Success` / `Failure` from `Rebilling::Strategy`.

Prefer explicit decision objects:

```ruby
decision.status
decision.reason
decision.plan
decision.diagnostics
```

This is easier to log, test, and debug.

## Mocking / Testing Support

Strategy unit tests should use simple snapshots, not database records.

For later consumer/service tests, use fake strategies:

```ruby
class FakeRebillingStrategy
  def initialize(decision)
    @decision = decision
  end

  def next_plan(_context, now: Time.current)
    @decision
  end
end
```

This lets `RetryManagerConsumer` tests focus on persistence and side effects without retesting strategy math.

## Test Plan

Pure unit specs should cover:

### RetryStep

- generated key includes percentage, basis, and delay;
- same percentage with different delays produces different keys;
- duplicate generated keys are rejected by strategy initialization;
- amount is based on invoice total by default;
- amount can be based on remaining balance;
- amount is capped by remaining balance;
- invalid percentage is rejected;
- invalid basis is rejected;
- invalid transition is rejected.

### Strategy Step Selection

- initial full-charge failure schedules first retry step;
- 75% failure schedules 50%;
- 50% failure schedules 25%;
- 25% failure can schedule 15%;
- final step failure exhausts retries;
- successful step repeats by default;
- `on_success: :next` transitions to the next step;
- `on_failure: :stop` exhausts retries;
- same percentage with different delays is tracked correctly by `retry_step_key`.

### Payment Method Policy

- primary method is preferred by default;
- active backup methods can be selected;
- inactive/expired/invalid methods are skipped;
- hard-declined methods are skipped;
- all eligible methods can be exhausted for a step before falling to lower amount;
- no eligible methods returns a no-method/exhausted decision.

### Guardrail tests

- max attempts reached returns exhausted;
- invoice already paid returns invoice-paid decision;
- inactive subscription returns subscription-inactive decision;
- pending/scheduled/processing attempt returns in-flight decision;
- non-retryable failure reason returns not-retryable decision.

### Diagnostics

- scheduled decisions include selected step, amount, payment method, and last attempt context;
- exhausted decisions include exhaustion reason and relevant context.

## Future Persistence Implications

Later implementation will likely need:

```text
payment_attempts.retry_step_key
payment_attempts.payment_method_id
payment_attempts.failure_category
payment_attempts.failure_code
```

And eventually:

```text
payment_methods
```

Minimum future `PaymentMethod` fields:

```text
id
customer_id
gateway_payment_method_id
status
kind
brand
last4
expires_at
primary
last_successful_at
last_failed_at
metadata
```

But this document focuses on the strategy model first. The initial implementation should keep strategy classes pure and independent of database persistence.

## Non-Goals for First Implementation

Do not implement yet:

- ML/smart retry timing;
- gateway-specific retry recommendations;
- customer timezone optimization;
- card account updater;
- notification delivery;
- automatic primary payment-method switching after backup success;
- admin-configured strategy records;
- a generalized rule engine.

The immediate goal is a deterministic, testable rebilling strategy that supports flexible partial amounts, delays, transitions, and payment-method waterfall behavior.
