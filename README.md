# GuilefulCharger

GuilefulCharger is a Rails API application that sketches a subscription billing workflow using PostgreSQL, RabbitMQ/Hutch, AASM state machines, dry-validation contracts/command schemas, and MoneyRails. The current codebase is best treated as a prototype: the core database tables and first-pass payment-processing objects exist, while retries, partial rebilling, payment-method management, audit logging, and production delivery guarantees are not complete.

## Current Implementation

### Runtime stack

- Rails API application, Ruby version from `.ruby-version`.
- PostgreSQL database with UUID primary keys and PostgreSQL enum columns.
- RabbitMQ messages via Hutch.
- MoneyRails for cent-based monetary columns.
- AASM for model state machines.
- dry-validation for message payload contracts declared through the `ActiveConsumer.message_schema` DSL at consumer boundaries.
- dry-validation for service command input schemas; declared keys are strictly validated and undeclared keyword arguments are preserved for `Dry::Initializer` options rather than silently dropped.
- Shared `ApplicationService` result helpers for structured `Failure[:code, metadata]` values and common subscription/payment-attempt metadata.
- `ActiveConsumer.consumer_options` DSL for Hutch quorum queue, dead-letter, delivery-limit, and single-active-consumer queue settings.
- RSpec test suite with FactoryBot.

### Implemented database-backed entities

#### Customer

Table: `customers`

Fields:

- `id`
- `name`
- `email` with a unique index
- `billing_address`
- timestamps

Current model associations:

- `has_many :subscriptions`
- `has_many :invoices, through: :subscriptions`

#### Subscription

Table: `subscriptions`

Fields:

- `id`
- `customer_id`
- `status`: `active`, `paused`, `cancelled`
- `amount_cents`
- `current_period_start`
- `current_period_end`
- AASM timestamp fields: `active_at`, `paused_at`, `cancelled_at`
- lifecycle metadata: `pause_reason`, `resumed_at`, `resume_reason`, `cancellation_reason`, `state_version`
- timestamps

Implemented behavior:

- Belongs to a customer.
- Has many invoices.
- Supports `active -> paused -> active`, `active -> cancelled`, and `paused -> cancelled` lifecycle transitions.
- Active subscriptions are billable and service-accessible.
- Paused subscriptions are not billable and not service-accessible.
- Pause/resume/cancel command services validate keyword input with `ApplicationService.input_schema` and return structured `Failure[:code, metadata]` results for non-happy paths.
- Resuming a paused subscription refreshes `active_at`, extends `current_period_end` by the pause duration, and re-enqueues existing scheduled payment attempts.
- Cancelled subscriptions are terminal.
- Can issue a draft invoice for its current billing period via `issue_new_invoice!`.
- Has a lock-and-recheck invoice issuing path via `issue_new_invoice_if_due!`.
- Has a uniqueness-protected invoice period through the invoice table/index.
- Has scopes intended to find active subscriptions due for billing and avoid duplicate invoices.

#### Invoice

Table: `invoices`

Fields:

- `id`
- `subscription_id`
- `status`: `draft`, `open`, `paid`, `partially_paid`, `not_paid`
- `amount_total_cents`
- `amount_paid_cents`
- `billing_period_start`
- `billing_period_end`
- `next_retry_at`
- `payment_attempts_count`
- AASM timestamp fields for each invoice status
- timestamps

Implemented behavior:

- Belongs to a subscription.
- Has many payment attempts.
- Validates one invoice per subscription billing period.
- `open_new!` moves an invoice from `draft` to `open` and creates the first payment attempt.

#### PaymentAttempt

Table: `payment_attempts`

Fields:

- `id`
- `invoice_id`
- `status`: `pending`, `scheduled`, `processing`, `completed`, `failed`
- `retry_strategy`: `initial`, `remaining_balance`
- `amount_attempted_cents`
- `attempt_number`
- `gateway_transaction_id`
- `failure_reason`
- `gateway_response`
- AASM timestamp fields for each payment-attempt status
- timestamps

Implemented behavior:

- Belongs to an invoice and updates `payment_attempts_count`.
- Can transition `pending -> scheduled -> processing`.
- Can transition `processing -> completed` on success.
- Can transition `processing -> failed` on failure.
- Stores gateway response data and transaction IDs.

### Implemented messaging/service flow

The intended flow in the current code is:

1. `PaymentScheduler#run!`
   - Finds active subscriptions due for billing.
   - Locks and re-checks each subscription inside `issue_new_invoice_if_due!` before creating a draft invoice.
   - Enqueues `invoice.created` in the outbox.

2. `InvoiceConsumer`
   - Consumes `invoice.created`.
   - Deduplicates the message with `ProcessedMessage`.
   - Validates the message payload with the consumer's `message_schema` contract.
   - Re-locks and re-checks invoice/subscription state and message version.
   - Opens a draft invoice.
   - Creates the first payment attempt.
   - Schedules the payment attempt.
   - Enqueues `billing.attempt.new` in the outbox with `payment_attempt_id` and subscription state version.

3. `BillingProcessorConsumer`
   - Consumes `billing.attempt.*`.
   - Deduplicates the message with `ProcessedMessage`.
   - Validates the message payload with the consumer's `message_schema` contract.
   - Loads a payment attempt.
   - Re-checks that the payment attempt is scheduled and the subscription is active.
   - Records `billing.payment.skipped` when the attempt is not currently processable.
   - Calls `ProcessPaymentService` with `PaymentGatewayApiMock`.
   - Enqueues `billing.payment.full.success` in the outbox on success.
   - Enqueues `billing.payment.failed` for gateway/insufficient-funds/system failures.
   - Raises on retryable system failures so Hutch can nack/dead-letter according to RabbitMQ policy.

4. `ProcessPaymentService`
   - Attempts to move a payment attempt to `processing`.
   - Calls a gateway object that responds to `#charge`.
   - Marks the attempt `completed` for gateway success.
   - Marks the attempt `failed` for insufficient funds, gateway failures, or mapped system errors.
   - Returns structured `Failure[:code, metadata]` results that include payment-attempt context.

## Current Gaps and Inaccurate Assumptions Found During Review

The previous documentation described several capabilities that are not implemented or are only partially sketched. The important gaps are below.

### Not implemented

- **Payment methods**: there is no `PaymentMethod` model or table. Customers do not store tokenized payment-method references.
- **Payments**: there is no separate `Payment` model/table. The implemented payment record is `PaymentAttempt`.
- **Audit logs**: there is no `AuditLog` model/table.
- **Refunds**: no refund entities or workflows exist.
- **Taxes and multi-currency**: no tax model/workflow exists. Money columns omit a currency column, so the app effectively assumes one currency.
- **Subscription plans**: no plan/catalog table exists.
- **User-facing cancellation flow**: subscription has a `cancel` event and cancellation fields, but there are no routes/controllers/API endpoints for users to cancel.
- **Partial rebilling strategy**: `RebillingStrategy` is a stub. The documented 75%/50%/25% retry ladder is not implemented.
- **Retry management**: `RetryManagerConsumer` only logs messages. It does not create retry attempts, compute retry amounts, or enforce retry limits.
- **Notifications**: `NotificationConsumer` only logs messages. No email/webhook/customer notification is implemented.
- **Invoice settlement**: successful payment attempts do not currently update `Invoice#amount_paid`, `Invoice#status`, subscription period dates, or remaining balances.
- **HTTP API**: the app only exposes Rails health check `/up`; no billing/customer/subscription API routes are defined.

### Partially implemented or currently inconsistent

- **Message delivery guarantees**: Hutch publisher confirms, an outbox table, and a processed-message inbox table are present, but consumers should still be treated as at-least-once. Consumers validate payloads, re-check PostgreSQL state/version before side effects, and record best-effort `billing.consumer.invalid_payload` outbox events for malformed payloads; exactly-once delivery is still not claimed. Invalid payloads are ACKed rather than retried because they are poison messages, so the invalid-payload observability event may be absent if recording it fails during a database outage.
- **Concurrency**: invoice scheduling uses database transactions, row-level subscription locks, and a unique index per subscription billing period. This helps prevent duplicate invoices, but it is not a full end-to-end concurrency/idempotency strategy.
- **PostgreSQL high availability**: local Docker and Kubernetes manifests define a single PostgreSQL instance with a PVC. They do not configure one synchronous standby plus asynchronous standbys or otherwise guarantee zero RPO.
- **Pause side effects are intentionally limited**: pausing prevents new billing and service access, and removes unstarted current-period draft invoices, but it does not void open invoices, refund completed payments, or cancel already-created payment attempts.

## Rebilling Status

The desired rebilling behavior is not complete. The current code has the following pieces:

- Payment gateway mock returns:
  - `success` for amounts from 1 to 500 cents.
  - `insufficient_funds` for amounts from 501 to 2000 cents.
  - `failed` for larger amounts.
  - `system_error` for amount `0`.
- Payment attempts can store failure reasons and gateway responses.
- Retry-related fields exist (`next_retry_at`, `retry_strategy`, `attempt_number`).

Missing pieces:

- No retry amount calculation.
- No retry scheduling workflow.
- No implementation of the 75%/50%/25% partial-charge ladder.
- No maximum retry enforcement beyond configuration placeholders.
- No invoice/subscription status updates after retry exhaustion.

## Local Development and Testing

### Prerequisites

- Ruby version from `.ruby-version`.
- Bundler.
- Docker and Docker Compose for containerized dependencies/test runs.

### Fetch dependencies locally

```bash
bundle install
```

### Fetch dependencies in Docker

```bash
make bootstrap
```

### Makefile help

`make` and `make help` print the available targets and a short description for each target:

```bash
make
make help
```

### Run tests with Docker

```bash
make test
```

Pass RSpec arguments through `RSPEC_ARGS`:

```bash
make test RSPEC_ARGS="spec/models/customer_spec.rb:123 --seed 123"
```

Run the full Docker workflow:

```bash
make test-all
```

Clean the Docker test environment:

```bash
make clean-docker-test
```

### Run tests locally without Docker

After installing gems and starting a local PostgreSQL compatible with `config/database.yml`:

```bash
bin/rails db:prepare RAILS_ENV=test
bin/rspec
```

During this review, direct local `bin/rspec` could not run because required gems were not installed locally. Use `bundle install` or `make bootstrap` first.

### Linting and security scan

```bash
make lint
make security-check
```

Pass tool-specific arguments through variables:

```bash
make lint RUBOCOP_ARGS="app/services"
make security-check BRAKEMAN_ARGS="--no-pager"
```

Local, non-Docker equivalents are still available:

```bash
bin/rubocop
bin/brakeman
```

## Deployment and Infrastructure Notes

- `.devcontainer/compose.yaml` starts Rails, PostgreSQL, and RabbitMQ for development/test use.
- RabbitMQ/Hutch is configured for durable publishing defaults, publisher confirms, manual acknowledgements, low prefetch, quorum consumer queues, dead-letter routing, retry queues with TTL/DLX, and single-active-consumer queue arguments. Per-consumer queue arguments are declared with `consumer_options` blocks.
- Subscription-scoped outbox messages are also mirrored to a consistent-hash exchange by `subscription_id` for shard-oriented processing/inspection; primary Hutch consumers still re-check PostgreSQL state/version because RabbitMQ delivery can be duplicate or out of order.
- `k8s/` contains development-style Kubernetes manifests for single-instance PostgreSQL, RabbitMQ, and Rails deployments.
- `config/deploy.yml` is the generated Kamal-style deployment scaffold and still contains placeholder hosts/image names.
- The repository does not currently include production-grade PostgreSQL HA, RabbitMQ HA, secret management, backup/restore, or disaster-recovery configuration.
