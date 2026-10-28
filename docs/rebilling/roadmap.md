# Rebilling roadmap and research notes

[← Rebilling guide](../rebilling.md) · [Algorithm design](algorithm-plan.md)

This document carries forward the gap analysis, proposed interfaces, priorities,
and research from `REBILLING_ALG.md`. Gap IDs remain stable for follow-up work.
The [algorithm design](algorithm-plan.md) provides the original planning context.

> [!IMPORTANT]
> Gap headings describe the original review, not a list of everything still
> missing. Use the status table below for the current implementation. External
> network rules, fees, vendor benchmarks, and rollout estimates are historical
> research notes from the original document; they were not revalidated in this
> documentation move and are not enforced application configuration.

**Contents:** [Current status](#current-status) · [Retry scopes](#two-retry-scopes-are-different-problems) ·
[Correctness](#critical-correctness-gaps) · [Network research](#industry-compliance-gaps) ·
[Operations](#operational-gaps) · [ML](#future-proofing-for-ml) ·
[Testing](#testing-and-debugging) · [Sources](#research-sources) ·
[Priorities](#prioritization-summary)

## Current status

**Implemented** means planner behavior exists; it does not imply a working retry
consumer or persistence layer. **Partial** means only part of the proposal or an
interface exists. Runtime classes live in [`app/services/rebilling/`](../../app/services/rebilling).

| ID | Status | Present / remaining boundary |
| --- | --- | --- |
| G1 | Partial | Deterministic plan key includes payment method; persistence uniqueness is missing. |
| G2 | Planned | Successful attempts do not reconcile invoices. |
| G3 | Partial | Version fields exist; no historical registry/selector or version-match enforcement. |
| G4 | Planned | No consumer locks an invoice and persists a retry plan. |
| G5 | Planned | No network-specific rolling counters or limits. |
| G5a | Partial | Classification fields exist; advice/refresh values stay nil/false and no network mapping is populated. |
| G6 | Partial | Authentication reasons stop business retries; no CIT/MIT/SCA integration or customer flow. |
| G7 | Partial | Tokenization metadata exists; payment-method selection does not use it. |
| G8 | Planned | No account updater or schedule preemption. |
| G9 | Partial | Context accepts timezone; timing ignores it. |
| G10 | Implemented | CRC32 jitter uses invoice, attempt number, and step key; default jitter is zero. |
| G11 | Partial | Notification intent exists but is always `:none`; no delivery ladder. |
| G12 | Partial | Policy returns `:pause_subscription`; it does not perform or trigger that action. |
| G13 | Partial | Recorder called once per decision, with a no-op default; no full persisted/replayable context. |
| G14 | Partial | Scoring option/interface exists but is not consulted. |
| G15 | Partial | Shadow-recording interface exists; no orchestration or persistence. |
| G16 | Planned | No A/B strategy selector. |
| G17 | Partial | Fixed-context invariant specs exist; no generated property testing. |
| G18 | Planned | No replay tool or persisted contexts. |
| G19 | Implemented | Optional trace records selected branches; it does not trace every guard. |
| G20 | Planned | No runtime strategy-to-DOT generator or snapshot tests. |
| G21 | Implemented | Plan includes exact/earliest/latest retry times; scheduler integration is missing. |
| G22 | Implemented | Retryable categories are configured at strategy level. |
| G23 | Partial | Generic reason classifier exists; raw gateway/network adapters are missing. |
| G24 | Implemented | Both amount bases can be mixed, rounded up, and capped by remaining balance. |
| G25 | Partial | Explicit keys and safe unknown-key outcomes exist; historical config loading is missing. |

The sections below retain the original proposals and research rationale. Later implementations should use the current status above to identify what still needs work.

## Two Retry Scopes Are Different Problems

Industry convention separates two retry scopes that share almost nothing structurally:

- **Synchronous, in-auth retry** (Stripe Adaptive Acceptance, Chargebee Pay): a sub-second retry that happens **inside the authorization flow** with mutated request fields (postal code formatting, card data normalization, network routing). Sees a single decline, decides to re-authorize once with adjustments, all before returning to the caller.
- **Asynchronous dunning retry** (the subject of this document): scheduled retries hours/days/weeks later, with new authorizations against possibly-different payment methods.

The current design implicitly addresses only the second. That is fine for now, but the strategy interface should make this scope explicit so a synchronous retry layer can be added later without confusion. Recommend naming the strategy `Rebilling::DunningStrategy` and reserving `Rebilling::AdaptiveAcceptanceStrategy` for a future synchronous component.

## Critical Correctness Gaps

### G1. No Plan Idempotency Key

`next_plan` returns a `Plan`, but the document never specifies what happens if the strategy is invoked twice for the same `(invoice, attempt_history)` state. With at-least-once message delivery from RabbitMQ, the consumer that creates the next `PaymentAttempt` may run twice.

**Fix**: Every `Plan` carries an `idempotency_key` derived deterministically from `(invoice_id, source_attempt_id, strategy_version, selected_step_key, payment_method_id)`. The persistence layer then stores attempts with a unique constraint on `(invoice_id, idempotency_key)` so duplicate calls produce duplicate keys and are rejected at the database level.

```ruby
Rebilling::Plan.new(
  step_key: :charge_25pct_invoice_total_after_60s,
  idempotency_key: "rebill:inv_123:pa_122:v1:charge_25pct_invoice_total_after_60s:pm_backup_1",
  ...
)
```

The strategy itself remains pure — it computes the key but does not enforce uniqueness. The consumer enforces.

### G2. Partial Payment Reconciliation Is Undefined

The doc says success at a step "follows that step's success transition" but never specifies how invoice state evolves. Open questions:

- When 25% of $1200 ($300) succeeds, does `Invoice#amount_paid_cents` become 300?
- Does `Invoice#status` become `partially_paid`?
- When does it become `paid`? When `amount_paid_cents >= amount_total_cents`?
- If the strategy keeps charging the next 25% chunk, does it charge 25% of the original total ($300) or 25% of remaining ($225)? (The doc argues for `:invoice_total` basis but doesn't reconcile this with partial-paid totals.)

**Fix**: Define an explicit partial-payment state machine that the strategy is aware of:

```text
Invoice transitions during retry recovery:
  open -> partially_paid: any retry succeeds with remaining > 0
  open -> paid:           retry succeeds and remaining == 0
  partially_paid -> paid: retry succeeds and remaining == 0
  open -> not_paid:       strategy returns :exhausted
  partially_paid -> not_paid: strategy returns :exhausted with remaining > 0
```

Strategy contract: `context.amount_remaining_cents` is **always** computed from `(amount_total_cents - amount_paid_cents)` at decision time and reflects whatever has been recovered so far. The strategy does not own the reconciliation; it only requires that the reconciler runs before the next strategy invocation.

### G3. Strategy Config Drift Breaks Lookups

`step_by_key.fetch(last_attempt.retry_step_key)` raises `KeyError` if a step was renamed, removed, or reordered between the time `last_attempt` ran and now. For long-running invoices (e.g., 14-day retry windows) this is realistic.

**Fix**: Strategies are versioned. Each `Decision` and each persisted `payment_attempts.retry_step_key` carries a `strategy_version`. Lookups use the historical strategy by version, not the current one.

```ruby
strategy_v1 = Rebilling::Strategy.load(version: 1)
strategy_v2 = Rebilling::Strategy.load(version: 2)
registry = Rebilling::StrategyRegistry.new
registry.register(strategy_v1)
registry.register(strategy_v2)

historical = registry.fetch(last_attempt.strategy_version)
historical.next_plan(context)
```

This also enables canary rollout and A/B testing.

### G4. Concurrent Strategy Invocation

Two paths can call the strategy: the periodic `PaymentScheduler` (sweep-based) and the `RetryManagerConsumer` (event-driven). Without coordination, both can produce a `Plan` for the same invoice at the same time.

**Fix**: The strategy is a pure function and stays pure. Coordination is the consumer's job: claim the invoice with `SELECT ... FOR UPDATE` before calling `next_plan` and persisting the result. Document this clearly so future consumers don't bypass the lock.

## Industry Compliance Gaps

### G5. Card Network Retry Rules Are Real and Have Per-Attempt Fees

Both major networks impose retry limits with associated fees and acquirer-monitoring penalties for non-compliance. These are not best-practice guidelines; they are billing rules:

**Visa — Excessive Reattempts (rules manual):**

- Limit: **15 reattempts of the same transaction within a 30-day window** for retry-eligible decline categories (raised toward 20 in 2025, but 15 remains the load-bearing published limit for safety).
- Fee per attempt above limit: **$0.10 domestic, $0.15 cross-border** per excess.
- The clock starts on the first declined authorization for that PAN+merchant+amount.

**Visa Acquirer Monitoring Program (VAMP, in force October 1, 2025; tightened April 1, 2026):**

- Replaces the older VDMP and VFMP programs.
- VAMP Ratio = (TC40 fraud reports + TC15 disputes) / TC05 settled, monthly, CNP only.
- "Excessive" merchant threshold: **>2.2% (2025) → >1.5% (April 2026)**, with **$8 per fraud/dispute event** above the threshold.
- **Enumeration Ratio**: >20% with ≥300K monthly enumeration count is flagged as card testing. **Aggressive retry patterns can be misread as enumeration** and contribute to this ratio. Daily-frequency retries on the same PAN are a red flag.
- Exclusion: merchants with <1,500 monthly fraud+dispute events.

**Mastercard — Transaction Processing Excellence (TPE), Excessive Authorization Attempts:**

- Limit: **≤10 declined attempts on the same PAN+merchant ID in 24 hours**, AND **≤35 attempts on same PAN+merchant+amount in 30 days** (lowered from 20 pre-October 2022).
- Fee per excess attempt: **$0.50 (US) / €0.55 (EU)**, effective January 2025.
- **CNP Decline Fee (effective February 1, 2026)**: $0.03 per decline with reason 79/82/83/51, plus **$0.78 CNP Advice Decline Fee** for re-submission within 30 days of certain advice codes.
- Regional variants: LATAM is tighter (7 attempts in 24h).

**Stored Credential Mandate (Visa + Mastercard, October 2018):**

- After a decline that allows reattempt, the merchant has **at least 14 days** to resubmit. Single-day-frequency retries after a hard decline violate this in spirit and risk acquirer scrutiny.

The current `max_attempts: 12` is within Visa/Mastercard hard caps but is silent on the windowing rules. Without window awareness, a 12-retry burst over 36 hours is a Mastercard TPE violation (only 10 in 24h are allowed).

**Fix**: Add a card-network-aware guardrail layer that consults a rolling window per (PAN, merchant) pair:

```ruby
Rebilling::NetworkComplianceGuard.new(
  visa: {
    max_retries_per_window: 15,
    window: 30.days,
    enumeration_safe_min_interval: 4.hours
  },
  mastercard: {
    max_retries_per_24h: 10,
    max_retries_per_amount_per_30d: 35,
    window: 30.days
  },
  amex: { max_retries: 4, window: 30.days },  # placeholder; verify before launch
  fallback: { max_retries: 4, window: 30.days },
  stored_credential_min_interval: 1.day  # respects 14-day spirit; tighter than required
)
```

The strategy consults this guard before scheduling a retry. If the limit is hit, the strategy either falls through to a different payment method (waterfall) or returns `:network_retry_limit_reached`.

Treat configured numbers as starting defaults that need legal/payments review per region. Card network rule books are the authoritative source.

### G5a. Merchant Advice Codes (MAC) Are the Network's Retry Recommendation

Mastercard appends a **Merchant Advice Code** to the authorization response (Authorization Optimizer Service Enhancement, AN 6042). This is the network telling you exactly what to do next. Ignoring MAC and using generic exponential backoff is strictly worse and risks excess fees:

| MAC | Meaning | Required action |
| --- | --- | --- |
| 01 | New account info available | Pull update from Account Updater (G8); retry with new credentials |
| 02 | Try again later (≤30 days) | Schedule retry within window |
| 03 | **Do not try again** | Stop. Retrying = fee + acquirer flag |
| 04 | Token requirements not fulfilled | Re-tokenize and retry |
| 21 | **Stop recurring payment requests** | Permanently mark payment method ineligible |
| 24 | Retry in next hour | Honor exact timing |
| 25 | Retry in 24 hours | Honor exact timing |
| 26 | Retry in 2 days | Honor exact timing |
| 27 | Retry in 4 days | Honor exact timing |
| 28 | Retry in 6 days | Honor exact timing |
| 29 | Retry in 8 days | Honor exact timing |
| 30 | Retry in 10 days | Honor exact timing |

MAC 24–30 are emitted only on insufficient-funds (51) declines for CNP recurring transactions, and they are the highest-quality retry-timing signal available without ML.

**Visa exposes a similar mechanism** via Decline Category Codes appended to declines:

- **Category 1 (issuer will never approve)**: 04, 07, 12, 14, 15, 41, 43, 46, 57, R0, R1, R3 — **zero retries permitted; any retry is fee-bearing.**
- **Category 2 (cannot approve at this time)**: 03, 19, 39, 51, 52, 53, 59, 61, 62, 65, 75, 78, 86, 91, 93, 96, N3, N4, Z5, 5C, 9G — retry-eligible.
- **Category 3 (data quality)**: 14, 54, 55, 70, 82, 1A, 6P, N7 — fix payment method data before retrying (G8 territory).
- **Category 4 (generic)**: retry later with normal logic.
- **R0/R1/R3 (revocation)**: customer requested cancellation; **retrying incurs €1 Stop Payment Service fee per retry** in some regions.

April 2024 reclassifications moved codes 62, 78, 93 from Category 1 → Category 2 (now retryable) and added Z5 ("Valid Account but Amount Not Supported") as Category 2.

**Fix**: The `FailureClassifier` (G23) is the integration point. The classifier owns the mapping from raw network code → canonical category, and from advice code → recommended retry timing. The strategy reads:

```ruby
classification = failure_classifier.classify(last_attempt.gateway_response)
# => Rebilling::FailureClassification.new(
#      category: :soft_decline,                  # canonical bucket
#      network_recommendation: :retry_in_4_days, # MAC 27 / Visa Cat 2 + cooldown
#      retryable: true,
#      requires_credential_refresh: false        # MAC 01 sets this true
#    )
```

The strategy can then **prefer the network recommendation over its configured delay** when present. The configured ladder is the fallback when no network recommendation exists or when the merchant intentionally overrides it.

This is the single highest-value addition in this gap analysis. MAC-aware retry timing is documented to outperform fixed schedules and is required for clean compliance.

### G6. SCA / 3DS / CIT-MIT Distinction Missing

For European customers under PSD2, off-session retry attempts must be flagged as Merchant-Initiated Transactions (MIT) and reference the original CIT (Cardholder-Initiated Transaction) authorization. Recurring fixed-amount MITs are exempt from SCA — but the **issuer** makes the final call, and soft declines for SCA reasons (e.g., decline code 1A "Additional Customer Authentication required") still happen.

Hard rules from public documentation:

- **Stripe explicitly states subscription payments do NOT auto-retry on `authentication_required`** declines: the customer must come on-session to complete 3DS. Retrying off-session is guaranteed to fail and consumes the retry budget.
- **Fixed-amount recurring exemption invalidates if amount or card changes** — variable-priced subscriptions (usage-based, mid-cycle plan changes) must use the MIT exemption flag explicitly, not the recurring-payment exemption.
- **One-year rule**: if no transaction occurred for >1 year, the MIT chain invalidates and a fresh CIT+SCA is required. This is the annual-renewal danger zone.
- **TRA (Transaction Risk Analysis) exemption thresholds** — depend on PSP fraud rate:
  - <€100 transaction: PSP fraud rate must be <0.13%
  - €100–€250: <0.06%
  - €250–€500: <0.01%

The current design treats every retry as semantically equivalent. It needs:

- A `transaction_initiator` field on `PaymentAttempt`: `:cardholder`, `:merchant`.
- An `original_credential_id` reference to the first successful CIT (for MIT chaining).
- An ability to **break** the chain and require a new CIT (with 3DS challenge) when the gateway returns `authentication_required` or when the chain is older than one year.
- An explicit "needs SCA" branch that **stops auto-retries and triggers customer-side authentication flow** (email link, in-app prompt).

**Fix**: Add a `Rebilling::AuthenticationPolicy` interface:

```ruby
policy.evaluate(context, last_attempt)
# => :off_session_eligible
# => :requires_fresh_cit             # SCA must complete via customer flow
# => :credential_chain_expired       # >1 year gap; fresh CIT needed
# => :exempt_amount_below_threshold  # TRA exemption applies
```

When the result is anything other than `:off_session_eligible`, the strategy returns `Decision[status: :customer_action_required]` with a `notification_intent` telling the notification consumer to send an authentication request to the customer. **Repeated off-session retries on `authentication_required` are guaranteed to fail and erode VAMP standing — the strategy must short-circuit immediately.**

### G7. Network Token vs Raw PAN Strategy Missing

Network tokens (Visa Token Service, Mastercard MDES) provide higher authorization rates and auto-refresh on card replacement. Published uplift numbers from primary sources:

| Source | Reported authorization uplift |
| --- | --- |
| Visa published | +4.6% approval rate |
| Visa internal (cited by processors) | +6% authorization, –30% fraud |
| Mastercard internal | +2.1% auth rate |
| Solidgate merchant base | +15% acceptance, +7.5% subscription retention |
| Acquired.com (lending) | +3% auth rate |
| Silverflow (MPE Berlin 2025) | +3–6% auth uplift |

The mechanism behind the uplift: network tokens carry issuer-verified trust signals plus auto-update on card reissue, eliminating the most common dunning trigger (expired/reissued card). The lift compounds with retry strategy because retries on stale PANs simply fail.

For long-lived subscriptions, raw PAN tokens are a worse default. The strategy should be able to:

- Distinguish `payment_method.kind` as `:network_token` vs `:raw_card_token` vs `:bank_account` vs `:wallet`.
- Prefer network-token-backed methods when retrying.
- Trigger re-tokenization when a raw-card method has been failing repeatedly.
- Track **network token coverage rate** as a leading indicator of dunning workload — a low NT rate predicts structurally higher retry volume.

**Fix**: Extend `PaymentMethodSnapshot` with `tokenization_kind` and let the `PaymentMethodPolicy` use it as a tiebreaker. Expose NT coverage rate as an operational metric.

### G8. Account Updater Integration

When a card expires or is replaced, Visa Account Updater (VAU) and Mastercard Automatic Billing Updater (ABU) provide updated card details. **Roughly 30% of cards in a typical issuer portfolio change per year** (number, expiration, or closure), per Visa's developer documentation. A retry strategy that does not consult these sources before declaring `:hard_decline` for "expired card" is leaving recovery on the table — published benchmarks show up to 30% of expiry-related failures recoverable via VAU/ABU.

Operational characteristics:

- **VAU is batch** (a few days before billing). Real Time VAU exists but only for Visa-on-Visa (no brand conversions). Pull-based for participating merchants.
- **ABU (Mastercard) is push-based** with similar coverage.
- Coverage limitation: enrollment is **per-issuer, opt-in**; many smaller banks do not participate.
- **MAC 01** is the network's signal that an update is available — the strategy must respect it (G5a).

The integration also creates an asynchronous schedule-preemption concern: when an account update arrives during an active dunning cycle, the schedule should be **invalidated and replaced with an immediate retry attempt** (Recurly's Exception A behavior).

**Fix**: Add a `Rebilling::CredentialRefresher` interface plus a "preemption" hook:

```ruby
refresher.refresh(payment_method)
# => :updated     -> retry can proceed with new credentials
# => :unchanged   -> credentials are still bad
# => :unavailable -> the network has no update; fall through to customer action

# Async path: when an updater webhook arrives:
Rebilling::Scheduler.preempt(invoice_id, reason: :credentials_refreshed)
# => cancels pending retries for the invoice and schedules an immediate attempt
```

The strategy itself remains pure; the refresher and the scheduler-preemption hook are integration concerns owned by the consumer layer. But the strategy must be able to evaluate `context.payment_method.last_credential_refresh_at` so it can prefer recently-refreshed methods.

## Operational Gaps

### G9. No Timezone or Time-of-Day Awareness

`retry_at: 1.minute.from_now` is server-local. Real-world signals:

- Charging at the customer's local 3am triggers fraud heuristics on some issuers ("unusual time").
- Charging on payday (varies by country: US ~1st/15th, UK ~25th, EU varies) succeeds materially better.
- B2B subscriptions perform better during business hours; B2C performs better evenings/weekends.

Even without ML, a non-trivial uplift comes from "respect customer local hours and do not retry between 11pm and 7am local."

**Fix**: Add a `Rebilling::ClockPolicy` interface that adjusts a candidate `retry_at` to fit a configured window:

```ruby
clock_policy.adjust(candidate_retry_at, customer_timezone, retry_window)
# => Time normalized to within the customer's allowed retry window
```

The first implementation can be a `BusinessHoursClockPolicy` with hardcoded 8am–8pm in customer timezone. ML can replace it later via the same interface.

### G10. No Retry Jitter

If 1000 invoices fail in a batch run and the strategy says "retry in 5 minutes," all 1000 retries fire in the same second. This thundering herd:

- Saturates the gateway connection pool.
- May trigger gateway rate limiting.
- Concentrates failures (gateway hiccups affect everyone simultaneously).

**Fix**: Add deterministic jitter as a property of `RetryStep`:

```ruby
Rebilling::RetryStep.new(
  percentage: 25,
  delay: 5.minutes,
  jitter: 0..120.seconds   # spread retries over 2 minutes
)
```

Determinism is preserved by seeding the jitter from `(invoice_id, attempt_number)` rather than randomness — same input, same output. Non-zero lower bounds are part of the retry window: `jitter: 30..120.seconds` means the retry is scheduled between `delay + 30s` and `delay + 120s`, not between `delay` and `delay + 120s`.

### G11. Notification Ladder Is Detached from Retry Schedule

Industry dunning ladders coordinate emails with retry attempts, e.g.:

```text
Day 0: payment failed                -> email "your payment failed"
Day 3: retry scheduled               -> email "we will retry on day 3"
Day 7: final retry scheduled         -> email "final attempt — please update"
Day 10: subscription will be paused  -> email "subscription paused"
```

The current design has the `NotificationConsumer` listening but no coordination with the retry decisions. Two consequences: (a) emails fire on every retry, spamming customers; (b) emails fire too late or too early to drive customer action.

**Fix**: The `Decision` carries a `notification_intent` field set by the strategy:

```ruby
Decision[
  status: :scheduled,
  plan: ...,
  notification_intent: :first_failure_warning  # or :none, :final_warning, :exhausted
]
```

The `RetryManagerConsumer` emits a notification event tagged with the intent. The `NotificationConsumer` decides actual delivery (rate-limit, channel, template).

### G12. Post-Exhaustion Behavior Is Silent

When the strategy returns `:exhausted`, what next?

- Cancel the subscription?
- Pause it (existing AASM state) until customer updates payment?
- Move the invoice to "manual collection" and notify operations?
- Retry with a longer cooldown next billing cycle?

Different SaaS products want different defaults. The doc has no explicit policy.

**Fix**: A `Rebilling::PostExhaustionPolicy` interface, called by the consumer (not the strategy) once `:exhausted` is returned:

```ruby
policy.handle(invoice, exhaustion_reason)
# => :pause_subscription
# => :cancel_subscription
# => :hold_for_manual_review
# => :retry_next_period
```

Default policy: `:pause_subscription`. Cancellation should be a separate, explicit downgrade after multiple exhausted invoices, never a single one.

## Future-Proofing for ML

### G13. No Feature Snapshot Persistence

For ML to ever work, you need a labeled dataset:

- Features at decision time (the full Context).
- Action taken (the Plan).
- Outcome (success / which kind of failure).

The current `diagnostics` field is "log-friendly" but not "ML-friendly." It captures selected fields, not the full feature space. A model trained 6 months from now needs **historical** Context snapshots, not just what was logged.

**Fix**: Add a `Rebilling::DecisionRecorder` interface called once per decision. Default implementation is a no-op. ML-backed implementation persists serialized `(Context, Decision, OutcomeRef)` tuples to a slow-growing table or warehouse.

```ruby
class DecisionRecorder
  def record(context, decision); end
end

# In strategy:
decision = compute_decision(context, now)
decision_recorder.record(context, decision)
decision
```

Important: the recorder persists everything serializable on Context, not just diagnostics. This means Context must be designed to be cleanly serializable from day one, even if no recorder is active.

### G14. No Pluggable Scoring Hook

The strategy currently makes deterministic step selections. ML predictions integrate naturally as a tiebreaker / re-orderer:

```ruby
Rebilling::ScoringPolicy.new
  .score(context, candidate_steps)
# => { step_key => probability_of_success_in_(0..1) }
```

The strategy can then be configured in two modes:

- `:rules_only` — ignore scoring (current behavior).
- `:rules_with_score_tiebreaker` — among rule-eligible steps, pick the highest-scoring.
- `:score_first` — pick the highest-scoring eligible step regardless of rule order (only when ML is mature).

Default is `:rules_only`. A `ScoringPolicy` interface defined now means later ML integration is a configuration change, not a refactor.

### G15. No Counterfactual Logging

A common ML pitfall: production runs strategy A, model is trained on outcomes from A, and there is no data on what would have happened under strategy B. Counterfactual logging records what each candidate strategy would have decided, even when only one was executed.

**Fix**: For shadow strategies (off-policy), the recorder also captures their decisions:

```ruby
shadow_decisions = shadow_strategies.map { |s| s.next_plan(context, now: now) }
decision_recorder.record_shadows(context, primary_decision, shadow_decisions)
```

This is "free" data for offline evaluation. Add the interface now; populate it once a second strategy variant exists.

### G16. No A/B Test Hook

Once strategy versioning (G3) and decision recording (G13) exist, A/B testing becomes deciding which strategy version to use per invoice:

```ruby
class StrategySelector
  def select_for(invoice)
    strategy_registry.fetch(version: hash_to_version(invoice.id))
  end
end
```

Stable per-invoice routing means:

- An invoice always sees the same strategy across retries (no cross-version drift).
- The hash-to-version function is deterministic and can implement gradual rollouts (10% → 50% → 100%).
- Outcomes can be attributed by strategy version cleanly.

Add the selector as an interface; first implementation always returns the latest stable version.

## Testing and Debugging

### G17. Add Property-Based Testing

Example-based tests check known cases. Property-based tests check invariants over generated inputs:

- **Invariant**: `decision.plan.amount_cents <= context.amount_remaining_cents` (always).
- **Invariant**: when a plan exists, `decision.plan.attempt_number == context.latest_terminal_attempt.attempt_number + 1`; attempt histories can be sparse.
- **Invariant**: For any context where the previous attempt's `retry_step_key` is unknown, the decision is `:not_retryable` rather than crashing.
- **Invariant**: `next_plan(context, now: fixed_now) == next_plan(context, now: fixed_now)` — deterministic with the same supplied clock.
- **Invariant**: the plan key is stable for the same invoice, source attempt, strategy version, step, and payment method, and changes when a key component changes.

Use [`rantly`](https://github.com/rantly-rb/rantly) or `rspec-rantly` to generate randomized contexts.

### G18. Add Replay Tooling

Production debugging often starts with: "this invoice retried at the wrong amount; why?"

A replay tool takes `(invoice_id, strategy_version)`, fetches the persisted Context+history at decision time, and re-runs the strategy with `trace: true`:

```ruby
Rebilling::Replay.run(invoice_id, strategy_version: 1, trace: true)
# => prints each branch evaluated, each step considered, each policy consulted, final decision
```

This requires recorded contexts (G13) but is otherwise straightforward. Add the recorder interface now to enable this later.

### G19. Add Trace Mode

`Decision` already carries `diagnostics`. Extend with optional `trace`:

```ruby
strategy.next_plan(context, now: now, trace: true)
# => Decision with .trace populated:
# [
#   { branch: :guard_invoice_paid, evaluated: true, result: false },
#   { branch: :guard_subscription_active, evaluated: true, result: true },
#   { branch: :step_selection, last_step: :charge_75pct..., transition: :on_failure, next: :charge_50pct... },
#   { branch: :payment_method_selection, candidates: [...], chosen: ... },
#   { branch: :amount_calculation, percentage: 50, basis: :invoice_total, calculated: 600, capped: 600 },
#   ...
# ]
```

Normal calls use `trace: false` and return no trace entries. Operations toggle a per-invoice trace flag for debugging.

### G20. Strategy Visualization

A 7-step strategy with `on_success`/`on_failure`/`on_failure_with_method_waterfall` becomes hard to read in YAML/code. Generate a Graphviz DOT representation for documentation and code review:

```ruby
Rebilling::Visualizer.dot(strategy)
# => DOT source rendering steps as nodes and transitions as labeled edges
```

CI can render it and attach to PRs. Reviewers see the actual flow, not the config.

## Smaller Issues Worth Addressing

### G21. `retry_at` Should Be a Window

A scheduler that says "retry at exactly 14:23:07" cannot batch optimally. A window:

```ruby
Plan[
  earliest_retry_at: 14:23:07,
  latest_retry_at: 14:25:07
]
```

…lets the scheduler batch retries for the same gateway/window into one connection and add jitter (G10) inside the window.

### G22. `retryable_failure_reasons` Per Step Is Over-Granular

The doc puts `retryable_failure_reasons` on each `RetryStep`. This is rarely useful — the same failure reason ("insufficient_funds") is retryable in step 3 but not in step 4? Almost never.

**Fix**: Hoist to the strategy level by default, allow per-step override only when needed. Reduces config noise.

### G23. `failure_category` Mapping Module Is Undefined

The doc lists categories (soft / hard / customer-action / technical) but does not specify the mapping from raw gateway codes. Different gateways have different code spaces (Stripe vs Adyen vs Braintree return different strings for "insufficient funds"). This must be a pluggable module per gateway:

```ruby
class StripeFailureClassifier
  def categorize(decline_code)
    case decline_code
    when "insufficient_funds" then :soft_decline
    when "stolen_card", "lost_card", "fraudulent" then :hard_decline
    when "expired_card", "incorrect_cvc" then :customer_action_required
    when "processing_error", "issuer_not_available" then :technical_failure
    else :unknown
    end
  end
end
```

The strategy depends on the **categorized** value, not the raw code. Add this interface now.

### G24. `:invoice_total` vs `:remaining_balance` Trade-Off Is One-Sided

The doc argues for `:invoice_total` for "stable chunk sizes." But after a partial recovery of, say, 50%, charging 25% of the original total ($300 of $1200) when only $600 is remaining means the *next* attempt is for half the remaining balance. That's a reasonable design — but charging 25% of the remaining ($150) is also reasonable for customers whose available funds are typically a fraction of full price.

**Fix**: Keep both bases as first-class options, and allow steps to mix. The recommendation should be "default to `:invoice_total` for predictability; switch to `:remaining_balance` for the tail steps after partial recovery." Document this trade-off and let it be a config choice, not a single-direction recommendation.

### G25. Step Key Generation Should Hash Stable Inputs Only

The current key generation includes normalized delay (`charge_25pct_invoice_total_after_300s`). If `delay` is later changed from `5.minutes` to `4.minutes` for the same step, the generated key changes — and persisted `payment_attempts.retry_step_key` values from the old key no longer resolve.

**Fix**: With strategy versioning (G3), this becomes a non-issue: the v1 strategy is loaded for v1 attempts, the v2 strategy for v2 attempts. Without versioning, key generation must be more conservative (don't include changeable fields in the key).

The cleaner long-term fix is versioning. Make versioning explicit before key generation matters.

## Recommended Module Layout

This is a proposed future layout. Existing classes live in `app/services/rebilling/`; registry, selector, replay, visualization, and several policy classes below do not exist yet.

```text
lib/rebilling/
├── dunning_strategy.rb              # Pure asynchronous dunning decision logic
├── strategy_registry.rb             # Multi-version lookup
├── strategy_selector.rb             # Per-invoice version assignment
├── retry_step.rb                    # Step config
├── payment_method_policy.rb         # Method waterfall
├── network_compliance_guard.rb      # Visa/MC retry-window enforcement
├── authentication_policy.rb         # CIT/MIT/3DS handling
├── credential_refresher.rb          # VAU/ABU integration
├── failure_classifier.rb            # Decline code -> category mapping
├── clock_policy.rb                  # Timezone/business-hours adjustment
├── post_exhaustion_policy.rb        # Pause/cancel/manual decisions
├── scoring_policy.rb                # ML hook
├── decision_recorder.rb             # Decision persistence for ML/replay
├── context.rb                       # Pure snapshot
├── attempt.rb                       # Pure snapshot of past attempt
├── payment_method_snapshot.rb       # Pure snapshot
├── plan.rb                          # Output type
├── decision.rb                      # Output type with status/reason/diagnostics
├── replay.rb                        # Production-debug tool
└── visualizer.rb                    # Graphviz DOT generator
```

Most of these are interfaces with no-op defaults. The "first implementation" defines all interfaces but only implements the rules-based strategy + a few default policies. Future ML / compliance / dunning work happens by replacing the no-op implementations, not by refactoring the strategy.

## ML Integration Roadmap

### Phase 1 — Data Collection (do this in the first implementation)

- Define `Context` to be fully serializable, including signals not used in v1 (customer tenure, MRR tier, gateway, country, etc.).
- Implement `DecisionRecorder` interface even if the default is a no-op.
- Persist `payment_attempts.retry_step_key`, `payment_attempts.strategy_version`, and `payment_attempts.failure_category`.

This makes the first implementation ML-ready without any ML.

### Phase 2 — Offline Analysis (months 1–3 after launch)

- Compute baseline metrics: recovery rate, time-to-recovery, retry-amount distribution, decline-category distribution.
- Identify segments where rules underperform: by gateway, by country, by customer tenure, by amount bucket.
- These are pre-ML insights; some will produce rule changes, not models.

### Phase 3 — Feature Engineering (months 3–6)

- Derive features: customer recency / frequency / monetary, time-since-last-success, declines-in-last-30-days, payment-method-age, BIN-level decline rate.
- Build a feature pipeline that runs both at training time (offline) and at decision time (online), with the same feature definitions. Feast / dbt / a small in-house store all work.

### Phase 4 — Online Inference (months 6+)

- Train a binary classifier or a calibrated per-step success probability model.
- Plug it in via `ScoringPolicy`.
- Start in `:rules_with_score_tiebreaker` mode (model only breaks ties).
- Once stable, advance to `:score_first` for selected segments.
- Always keep `:rules_only` available as a fallback.

### Phase 5 — Continuous Learning

- Retrain on rolling windows.
- Monitor calibration (does predicted P(success) match observed?).
- Monitor counterfactuals (would the rules-only strategy have done better?).
- Roll back to rules-only via configuration, not deploy, if something regresses.

The architectural hooks (versioning, recorder, scoring, counterfactual) all exist from day one. The model itself is the only ML-specific addition.

## Updated Test Plan

### Pure Unit Tests (no DB)

- All the cases listed in the original "Test Plan" section, plus:
- `IdempotencyKey` is stable across calls and unique across distinct inputs.
- `FailureClassifier` covers every code returned by the gateway mock and falls back to `:unknown` for unmapped codes.
- `ClockPolicy` returns retry times within the configured window for any input timezone.
- `NetworkComplianceGuard` correctly counts retries within rolling windows.

### Property-Based Tests (G17)

- See invariants listed there.

### Replay Tests (G18)

- Fixture: a recorded `(Context, ExpectedDecision)` pair from production.
- Test: running the historical strategy version against the fixture produces the expected decision byte-for-byte.
- Add fixtures over time as production incidents occur.

### Visualization Diff Tests (G20)

- Generate DOT output for the default strategy.
- Snapshot test it. Strategy config changes that change the visualization fail the test until the snapshot is regenerated and reviewed.

### Trace Mode Tests (G19)

- Run the strategy with `trace: true` for representative scenarios.
- Assert each expected branch is recorded in the trace.

## Recovery Rate Benchmarks

What does "good" look like? Published benchmarks (vendor-stated, verify before quoting externally):

| Recovery rate of at-risk transactions | Tier |
| --- | --- |
| <50% | Weak — likely missing basic dunning |
| 50–65% | Average rules-based |
| 65–80% | Good (mature dunning) |
| >80% | Excellent (typically requires ML or heavy tuning) |

Specific products:

- **Recurly Intelligent Retries**: published claim of **73%** recovery of at-risk transactions; recovered subscriptions add an average of 12 months of lifetime.
- **Stripe Smart Retries**: vendor-stated 15–25% on soft declines, 5–8% on hard declines; recovered subscriptions continue ~7 more months on average.
- **ProfitWell 2024 State of Subscription Payments**: specialized recovery tools recover **67% more revenue** than processor defaults.

Involuntary churn rates by ARPC (Slicker 2025):

| ARPC | Median involuntary churn | At-risk threshold |
| --- | --- | --- |
| $5–15/mo | 1.8% | 4.2% |
| $15–50/mo | 1.5% | 3.8% |
| $50–100/mo | 1.2% | 2.9% |
| $100+/mo | 0.8% | 2.1% |

Involuntary churn typically accounts for **20–40% of total churn** with standard dunning, dropping to **5–15% with sophisticated systems**. Stripe's research attributes **~25% of lapsed subscriptions** to payment failures specifically.

Operational metrics worth instrumenting from day one (so the data exists for ML in Phase 1):

- Recovery rate per attempt number.
- Deduplicated approval rate vs. raw approval rate.
- Average attempts for **successful** recoveries vs. average attempts overall (a wide gap = retrying past diminishing returns).
- Net recovery ROI: revenue recovered − retry-fee costs (per G5, fees are real).
- Recovery rate by decline category and by customer tenure cohort.
- Network token coverage rate (G7).
- Account Updater hit rate (G8).
- Retry success by hour-of-day in customer timezone (G9).

## Reference Defaults (Industry-Validated Starting Points)

Where the original document recommended specific numbers, the research suggests these starting points:

- **Stripe default**: 8 retries within 2 weeks. Reasonable mid-aggressiveness baseline.
- **Recurly hard cap**: 20 attempts total OR 60 days since invoice creation. Use as upper bound.
- **Chargebee Smart Dunning**: up to 12 retries. Direct Debit (SEPA/ACH): max 2 retries (gated on PSP confirmation, 5–7 business days).
- **Mastercard MAC 24–30**: when present, override configured delays.
- **Stored credential 14-day floor**: do not schedule more than ~one retry per day after a hard decline; respect spirit of the mandate.

The original document's example (`max_attempts: 12`) is in range. Adding window awareness (G5) and MAC awareness (G5a) is the necessary upgrade.

## Research sources

Source links retained from the original research notes. Check the publisher and applicable version before relying on a rule, fee, or benchmark.

**Stripe**:

- Smart Retries engineering: <https://stripe.com/blog/how-we-built-it-smart-retries>
- Smart Retries docs: <https://docs.stripe.com/billing/revenue-recovery/smart-retries>
- Adaptive Acceptance AI 2024–2025: <https://stripe.com/blog/ai-enhancements-to-adaptive-acceptance>
- Decline codes: <https://docs.stripe.com/declines>
- Optimizing authorization rates: <https://stripe.com/guides/optimizing-authorization-rates>
- Subscription retries for failed 3DS: <https://support.stripe.com/questions/subscription-retries-for-failed-3d-secure-authorizations>

**Recurly**:

- Intelligent Retries: <https://docs.recurly.com/recurly-subscriptions/docs/retry-logic>
- ML engineering blog: <https://recurly.com/blog/using-machine-learning-to-optimize-subscription-billing/>
- Subscriber retention benchmarks: <https://recurly.com/research/subscriber-retention-benchmarks/>

**Chargebee**:

- Smart Dunning: <https://www.chargebee.com/docs/payments/2.0/kb/payments/what-is-smart-dunning>
- Dunning v2: <https://www.chargebee.com/docs/payments/2.0/dunning/dunning-v2>

**Visa**:

- VAMP Fact Sheet 2025: <https://corporate.visa.com/content/dam/VCOM/corporate/visa-perspectives/security-and-trust/documents/visa-acquirer-monitoring-program-fact-sheet-2025.pdf>
- Stored Credential Framework: <https://usa.visa.com/content/dam/VCOM/global/support-legal/documents/stored-credential-transaction-framework-vbs-10-may-17.pdf>
- PSD2 SCA: <https://www.visa.co.uk/dam/VCOM/regional/ve/unitedkingdom/PDF/visa-preparing-for-psd2-sca-publication-version-1-1-05-12-18-002-final.pdf>
- Excessive Reattempts (Payway summary): <https://www.payway.com/visa-excessive-reattempts-rule-fees>
- VAU developer FAQ: <https://developer.visa.com/capabilities/vau/vau-faq>

**Mastercard**:

- Transaction Processing Rules: <https://www.mastercard.us/content/dam/public/mastercardcom/na/global-site/documents/transaction-processing-rules.pdf>
- Merchant Advice Codes (Chargeback Gurus summary): <https://www.chargebackgurus.com/blog/mastercard-merchant-advice-codes>
- Network updates 2024 (Braintree): <https://developer.paypal.com/braintree/articles/risk-and-security/compliance/network-updates/2024/mc-su24>

**Other gateways**:

- Adyen raw acquirer responses: <https://docs.adyen.com/development-resources/raw-acquirer-responses>
- Braintree decline codes: <https://developer.paypal.com/braintree/articles/control-panel/transactions/declines>
- Sift decline category guide: <https://developers.sift.com/guides/decline-category-guide>
- Yuno MAC reference: <https://docs.y.uno/reference/payments/status-and-response-codes/merchant-advice-codes-mac>

**ML on payment retries**:

- Dropbox ML for payments: <https://dropbox.tech/machine-learning/optimizing-payments-with-machine-learning>
- Predictive AI Models for Reducing Payment Failures (IJFT 2025): <https://iaeme.com/MasterAdmin/Journal_uploads/IJFT/VOLUME_2_ISSUE_1/IJFT_02_01_002.pdf>

## Prioritization Summary

The full list above is intentionally exhaustive. For the first implementation, treat these as priority tiers:

**Tier 1 — Build now, in the first implementation**:

- G1 (idempotency keys).
- G2 (partial reconciliation state machine).
- G3 (strategy versioning).
- G4 (concurrency contract documented).
- G5a-stub (FailureClassifier interface, with the MAC/Visa-Category mapping table populated even if the strategy does not yet honor `network_recommendation`). The mapping data is the highest-leverage piece of compliance and is cheap to add.
- G13 (decision recorder interface, even if no-op).
- G14 (scoring policy interface, even if no-op).
- G19 (trace mode on Decision).
- G21 (retry window: `earliest_retry_at` + `latest_retry_at`).
- G22 (hoist `retryable_failure_reasons` to strategy level).
- G23 (failure classifier interface — the FailureClassification value type).
- G10 (jitter).
- G12 (post-exhaustion policy interface).

**Tier 2 — Add when first real customer scenarios demand it**:

- G5a-honor (strategy actually uses `network_recommendation` to override its configured delay when present).
- G9 (timezone-aware clock policy).
- G11 (notification intent on decision).
- G15 (counterfactual logging).
- G16 (A/B selector).
- G17 (property-based tests).
- G18 (replay tooling).
- G20 (Graphviz visualization).

**Tier 3 — Compliance, do before scaling beyond a small merchant footprint**:

- G5 (network compliance guard with per-window counters — required to avoid Visa/Mastercard fees once volume is meaningful).
- G6 (SCA / CIT-MIT / `authentication_required` short-circuit — required for any European customer).
- G7 (network token preference and coverage tracking — material auth-rate uplift).
- G8 (account updater integration with schedule preemption).

**Tier 4 — ML enablement**:

- Phases 1–5 above. Phase 1 work (Context full serializability, DecisionRecorder no-op, full feature persistence on `payment_attempts`) is folded into Tier 1 so ML readiness is free.
- Industry signals to encode as features once data is collected: gateway, BIN, country, debit/credit/prepaid, customer tenure, ARPC tier, time-since-last-success, hour-in-customer-tz, day-of-month, MAC value if present, account-updater hit recency.

The tiers preserve the original goal: a deterministic, testable rebilling strategy. They add the seams that prevent painful retrofits when compliance, ML, or operations work lands later. The single highest-leverage addition is the FailureClassifier (G5a/G23) — even just having the Mastercard MAC table mapped and persisted produces actionable retry-timing data for Tier 2/3 work and is a precondition for clean compliance work.
