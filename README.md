# GuilefulCharger

GuilefulCharger is a Rails API application that sketches a subscription billing workflow using PostgreSQL, RabbitMQ/Hutch, AASM state machines, and MoneyRails. The current codebase is best treated as a prototype: the core database tables and first-pass payment-processing objects exist, while retries, partial rebilling, payment-method management, audit logging, and production delivery guarantees are not complete.

## Current Implementation

### Runtime stack

- Rails API application, Ruby version from `.ruby-version`.
- PostgreSQL database with UUID primary keys and PostgreSQL enum columns.
- RabbitMQ messages via Hutch.
- MoneyRails for cent-based monetary columns.
- AASM for model state machines.
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

Current model associations include `has_many :subscriptions`. The model also declares `has_many :invoices` and `has_many :payments`, but those associations do not match the current schema because invoices belong to subscriptions and there is no `payments` table/model.

#### Subscription

Table: `subscriptions`

Fields:

- `id`
- `customer_id`
- `status`: `active`, `cancelled`
- `amount_cents`
- `current_period_start`
- `current_period_end`
- AASM timestamp fields: `active_at`, `cancelled_at`
- `cancellation_reason`
- timestamps

Implemented behavior:

- Belongs to a customer.
- Has many invoices.
- Can issue a draft invoice for its current billing period via `issue_new_invoice!`.
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
   - Locks rows with `FOR UPDATE SKIP LOCKED`.
   - Creates a draft invoice.
   - Publishes `invoice.created`.

2. `InvoiceConsumer`
   - Consumes `invoice.created`.
   - Opens a draft invoice.
   - Creates the first payment attempt.
   - Publishes `billing.attempt.new`.

3. `BillingProcessorConsumer`
   - Consumes `billing.attempt.*`.
   - Loads a payment attempt.
   - Calls `ProcessPaymentService` with `PaymentGatewayApiMock`.
   - Publishes `billing.payment.full.success` on success.

4. `ProcessPaymentService`
   - Attempts to move a payment attempt to `processing`.
   - Calls a gateway object that responds to `#charge`.
   - Marks the attempt `completed` for gateway success.
   - Marks the attempt `failed` for insufficient funds, gateway failures, or mapped system errors.

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

- **Message delivery guarantees**: Hutch publisher confirms are configured, but the app does not implement an outbox, inbox, idempotency keys, deduplication table, or transactional message publishing. Treat RabbitMQ delivery as at-least-once and make consumers idempotent before depending on stronger guarantees.
- **Concurrency**: invoice scheduling uses database transactions and `FOR UPDATE SKIP LOCKED`, and invoices have a unique index per subscription billing period. This helps prevent duplicate invoices, but it is not a full end-to-end concurrency/idempotency strategy.
- **PostgreSQL high availability**: local Docker and Kubernetes manifests define a single PostgreSQL instance with a PVC. They do not configure one synchronous standby plus asynchronous standbys or otherwise guarantee zero RPO.
- **Payment attempt state flow**: `Invoice#open_new!` creates a `pending` payment attempt, but `ProcessPaymentService` starts from `scheduled`. There is currently no implemented scheduler/consumer step that schedules the initial pending attempt before processing.
- **Consumer payloads**: `InvoiceConsumer` publishes `payment_attempt_id`, which is what `BillingProcessorConsumer` expects. `BillingService`, however, builds a different payload and references an undefined `subscription` method.
- **Consumer implementation details**: several consumers define `find_payment_attempt` methods that reference `message` outside the `process(message)` method scope.
- **Subscription state machine**: the enum only supports `active` and `cancelled`, while some AASM transitions reference `paused`.
- **Customer associations**: `Customer#has_many :invoices` and `Customer#has_many :payments` are stale relative to the schema.

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
bin/rubocop
bin/brakeman
```

## Deployment and Infrastructure Notes

- `.devcontainer/compose.yaml` starts Rails, PostgreSQL, and RabbitMQ for development/test use.
- `k8s/` contains development-style Kubernetes manifests for single-instance PostgreSQL, RabbitMQ, and Rails deployments.
- `config/deploy.yml` is the generated Kamal-style deployment scaffold and still contains placeholder hosts/image names.
- The repository does not currently include production-grade PostgreSQL HA, RabbitMQ HA, secret management, backup/restore, or disaster-recovery configuration.
