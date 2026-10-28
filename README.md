# GuilefulCharger

GuilefulCharger is a Rails API application that sketches a subscription billing workflow using PostgreSQL, RabbitMQ/Hutch, AASM state machines, dry-validation contracts/command schemas, and MoneyRails. The current codebase is best treated as a prototype: the core database tables and first-pass payment-processing objects exist, while retries, partial rebilling, payment-method management, audit logging, and production delivery guarantees are not complete.

## Current Implementation

### Runtime stack

- Rails API application, Ruby 4.0.9 from `.ruby-version` and `Gemfile`.
- PostgreSQL 18.6 database with UUID primary keys, PostgreSQL enum columns, and `uuidv7()` support for time-ordered outbox message IDs.
- RabbitMQ 4.4.0 messages via Hutch.
- MoneyRails for cent-based monetary columns.
- AASM for model state machines.
- dry-validation for message payload contracts declared through the `ActiveConsumer.message_schema` DSL at consumer boundaries.
- dry-validation for service command input schemas; declared keys are strictly validated and undeclared keyword arguments are preserved for `Dry::Initializer` options rather than silently dropped.
- Shared `ApplicationService` result helpers for structured `Failure[:code, metadata]` values and common subscription/payment-attempt metadata.
- `ActiveConsumer.consumer_options` DSL for Hutch quorum queue, dead-letter, delivery-limit, and single-active-consumer queue settings.
- RSpec test suite with FactoryBot.
- Outbox partition maintenance uses PostgreSQL extensions: `pg_partman` for published-message partition retention and `pg_cron` for scheduled database maintenance.

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
   - Validates the message payload with the consumer's `message_schema` contract.
   - Re-locks and re-checks invoice/subscription state and message version.
   - Uses invoice domain state for idempotency: only draft invoices can be opened, so duplicate deliveries for already-open invoices are no-ops.
   - Opens a draft invoice.
   - Creates the first payment attempt.
   - Schedules the payment attempt.
   - Enqueues `billing.attempt.new` in the outbox with `payment_attempt_id` and subscription state version.

3. `BillingProcessorConsumer`
   - Consumes `billing.attempt.*`.
   - Validates the message payload with the consumer's `message_schema` contract.
   - Loads a payment attempt.
   - Uses payment-attempt domain state for idempotency: terminal or already-processing attempts are duplicate/no-op deliveries.
   - Re-checks that the payment attempt is scheduled and the subscription is active.
   - Records `billing.payment.skipped` when the attempt is not currently processable for non-duplicate reasons.
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

### Outbox partitioning and retention

`outbox_messages` uses PostgreSQL native partitioning so the publisher works against a small hot unpublished partition instead of a table dominated by historical published rows.

The partition shape is:

```text
outbox_messages
├── outbox_messages_unpublished  -- published_at IS NULL
└── outbox_messages_published    -- published_at IS NOT NULL
    ├── daily published partitions managed by pg_partman
    └── default published partition for safety
```

Important behavior:

- Outbox IDs are generated with PostgreSQL 18 `uuidv7()` so they are globally unique and time-ordered enough for publisher claim ordering.
- `outbox_messages` intentionally omits `created_at`; creation/backlog age is derived from `uuid_extract_timestamp(id)`.
- The publisher claims unpublished work in `id` order with `FOR UPDATE SKIP LOCKED` and a small batch size.
- Setting `published_at` moves a row from `outbox_messages_unpublished` into the published partition tree.
- Published rows are retained for 7 days by `pg_partman` and then removed by dropping old published partitions.
- Unpublished rows, including failed or stale-locked rows, are never removed by retention. A multi-day publisher backlog grows the unpublished partition but is not deleted by the 7-day published retention policy. Monitor backlog age with `MIN(uuid_extract_timestamp(id)) WHERE published_at IS NULL`.
- Published outbox history is operational/debug data only. Long-term audit history should be exported outside the primary database if it becomes necessary.
- `pg_cron` schedules `pg_partman` maintenance and periodic reindexing of the hot unpublished partition indexes. The unpublished partition is expected to remain tiny, so scheduled reindex jobs use plain `REINDEX INDEX` because `REINDEX INDEX CONCURRENTLY` cannot run inside pg_cron's transaction wrapper.

Because partitioning and `pg_partman` metadata are PostgreSQL-specific, migrations are the schema source of truth for the outbox. Rails schema dumps are disabled because schema-only dumps do not preserve `pg_partman`'s extension-managed retention configuration.

### Consumer idempotency

The app does not maintain a generic processed-message inbox table. RabbitMQ delivery is treated as at-least-once, and consumers must be safe under duplicate delivery by checking PostgreSQL domain state under locks before side effects.

Current idempotency boundaries:

- `InvoiceConsumer` only opens draft invoices; duplicate deliveries for already-open invoices are no-ops.
- `BillingProcessorConsumer` only charges scheduled payment attempts; duplicate deliveries for processing, completed, or failed attempts are no-ops.
- Stale subscription-scoped messages carry state versions and are ignored/skipped after the current PostgreSQL state is reloaded.
- Future consumers that perform external side effects, such as notifications or retry creation, must introduce a domain idempotency key or uniqueness constraint for that side effect instead of relying on a generic inbox table.

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

- **Message delivery guarantees**: Hutch publisher confirms and an outbox table are present, but consumers should still be treated as at-least-once. There is intentionally no generic processed-message inbox table; consumers validate payloads and re-check PostgreSQL domain state/version before side effects. Malformed payloads are ACKed as poison messages and recorded best-effort as `billing.consumer.invalid_payload` outbox events, so the invalid-payload observability event may be absent if recording it fails during a database outage. Exactly-once delivery is not claimed.
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

- Ruby 4.0.9 from `.ruby-version` and enforced by `Gemfile`.
- Bundler 4.0.23, pinned in `Gemfile.lock`.
- Docker and Docker Compose for containerized dependencies/test runs.

### Fetch dependencies locally

```bash
gem install bundler -v 4.0.23
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

### Sorbet and dry-rb

Sorbet 0.6 and Tapioca 0.20 provide gradual static checking. `sorbet-runtime`
loads with the application; the checker and interface generator are development
and test dependencies. This follows [Sorbet's adoption guide](https://sorbet.org/docs/adopting):
use Tapioca rather than the legacy `srb init`, and commit generated RBIs.
The lockfile targets ARM64 and x86-64 on macOS/Linux, matching the native tooling
binaries; the previous 32-bit ARM/x86 entries were removed during resolution.

```bash
bundle exec srb tc                 # Static check; no Rails boot or database
bin/tapioca gems --verify          # Check gem RBI versions against the lockfile
CI=1 bin/tapioca dsl --verify       # Check Rails DSL interfaces; needs test DB
```

Use `make typecheck` and
`make rbi-verify`. `make check` runs these alongside tests and linting. CI checks
types and gem interfaces separately, and checks DSL interfaces after preparing
the test database. Tapioca's configured DSL environment is `test`, which avoids
connecting Hutch to RabbitMQ during generation.
Use `CI=1` for DSL commands so Rails eagerly loads the same framework controllers
locally and in CI. Tapioca's `dsl.environment` controls the Rails environment;
setting `RAILS_ENV` on a DSL command does not override that configuration.
The Make targets start the containers, and `rbi-verify` prepares the test database
before verification, including under parallel Make execution. CI runs specs even
if the separate interface verification step fails, provided database setup passed.

After updating dependencies or changing a model/DSL, regenerate and commit the
relevant interfaces:

```bash
bin/tapioca gems
RAILS_ENV=test bin/rails db:prepare
CI=1 bin/tapioca dsl
bundle exec srb tc
```

Generated files in `sorbet/rbi/gems`, `annotations`, and `dsl` should not be edited
by hand. There are currently no manual shims. Gem verification
checks presence and version metadata; after upgrading Tapioca itself, use
`bin/tapioca gems --all` to regenerate every gem interface. Community annotations
can be refreshed explicitly with `bin/tapioca annotations`.

Existing files without a sigil remain `typed: false`: Sorbet checks syntax and
constant resolution, but does not check their method bodies. `Rebilling::Decision`
starts at `typed: true` with a typed return from the factory used by billing. Promote files gradually
and add `sig` declarations with tests; a passing baseline does not mean the entire
application is statically typed.

Method signature violations raise in development/test. Production reports call
mismatches, signature builder errors, and signature validation errors through
[Sorbet's supported handlers](https://sorbet.org/docs/tconfiguration). Logs include
the method, violation kind, and source location, without argument/return values
or exception messages. Reports are limited to once per method/kind per minute,
with bounded tracking memory. Ruby exceptions inside lazy signature blocks
(such as an undefined constant), dry-rb validation errors, and explicit Sorbet
assertions still raise. Types named in signatures must exist at runtime.
The reporting boundary suppresses reflection and logger failures. Property errors
include the property name and external caller; Sorbet's nil-signature callback
does not supply an owning class. The initializer-required policy is excluded from
Zeitwerk reloading; restart the process after changing it.
The production image excludes development/test gems
and the RBI tree; only `sorbet-runtime` ships for application signatures.

Compatibility findings (verified October 28, 2026):

- All ten dry-rb dependencies were checked against stable RubyGems releases.
  `dry-configurable` was updated from 1.3.0 to 1.4.0; `dry-core` 1.2.0,
  `dry-inflector` 1.3.1, and `dry-logic` 1.6.0 were already current, along with
  the application dependencies below. `dry-configurable` 1.4 requires Ruby 3.3+
  and adds `Config#to_data`; see its [release notes](https://github.com/dry-rb/dry-configurable/releases/tag/v1.4.0).
  The project uses Ruby 4.0.9.
- **dry-types 1.9.1:** runtime coercions and constraints remain in dry-rb.
  `Dry.Types` generates a module dynamically, which [Sorbet cannot use as a static ancestor](https://sorbet.org/docs/error-reference#4002).
  Only `config/initializers/dry.rb` uses `typed: ignore`; the tested local
  `DryTypeNamespaces` compiler generates both namespaces from the runtime catalog,
  including inherited constants and dry-types builder methods, without duplicated
  hand-kept shim lists.
  `Rebilling::Types` includes the named
  global module. These validator objects are explicitly untyped and must not be
  used as Sorbet class types; use `::Integer`, `::String`, `T.nilable`, etc. in signatures.
- **dry-monads 1.11.0:** the public `Dry::Monads::Result::Mixin` makes ancestors
  visible to Sorbet. Reflected gem RBIs expose the API, but do not infer generic
  success/failure payloads or narrowing from `success?`. Add explicit signatures
  and typed boundary objects as each service is adopted.
- **dry-initializer 3.2.0 and dry-struct 1.8.1:** Tapioca 0.20 has no bundled DSL
  compilers for their generated constructors/readers. Those APIs remain untyped
  until covered by a reviewed RBI or a tested local compiler. Arbitrary coercion
  constructors must not be assumed to return their underlying nominal type.
- **dry-validation 1.11.1:** runtime contracts continue to validate inputs. Sorbet
  does not infer a typed record from a successful schema result; translate validated
  data into a typed object or add an explicit signature at the service boundary.

We do not install [dry-monads-sorbet](https://github.com/bellroy/dry-monads-sorbet)
(archived in 2023) or [tapioca-compilers-dry_struct](https://github.com/YukiJikumaru/tapioca-compilers-dry_struct)
(last repository update in 2022). The [upstream compiler discussion](https://github.com/Shopify/tapioca/issues/1210)
describes the adapter approach, but neither adapter has been validated here against
Ruby 4, current dry-rb, and Tapioca 0.20. Local, tested interfaces are the next step
when expanding static coverage of these DSLs.

### Dependabot and generated interfaces

Dependabot checks gems and GitHub Actions daily. Minor/patch updates to `dry-*`
are grouped together, as are the Sorbet/Tapioca toolchain dependencies. Major
updates remain individual PRs. Docker image updates are not configured here.

Bundler PRs opened or updated by Dependabot trigger `Dependabot RBI generation`.
It checks out the exact PR head without persisted credentials, prepares a disposable
test database, and regenerates gem and Rails DSL interfaces. Ordinary updates use
incremental `bin/tapioca gems`; changes to Tapioca, RBI, Rubydex, or Spoom trigger
`--all` to rebuild interfaces affected by reflection tooling. Sorbet patch bumps
use incremental generation. Both workflows use `script/ci_postgres.sh` for matching
database/pg_cron configuration. Generation has no publishing credentials, and does
not wait for application specs or a separate typecheck. The App's resulting commit
must pass normal CI before merge.

`Publish Dependabot RBIs` runs from the default branch after successful generation.
It downloads the JSON artifact into a temporary directory, validates the originating
run and current PR, and permits only regular RBI content under `sorbet/rbi/gems`
and `sorbet/rbi/dsl`. Non-RBI generator metadata such as `.gitattributes` is excluded
from collected artifacts. The publisher rejects `sorbet/rbi/shims/**` and annotation
paths, forks, source/workflow changes, traversal paths, oversized content, and
incomplete PR file listings. Closed/merged PRs and superseded heads skip successfully,
including races during publication. A dedicated GitHub App commits the interfaces
with an atomic expected-head check. The App's
commit triggers normal CI; it does not trigger another generation run because
generation requires the Dependabot actor. No dependency update is automatically
merged, and the existing interface checks remain enabled.

Generated commits include `[dependabot skip]`, which [allows Dependabot to rebase
over those commits](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/manage-your-dependency-security/manage-dependabot-prs#allowing-dependabot-to-rebase-and-force-push-over-extra-commits).
After a rebase, interfaces are regenerated for the new dependency head. This
marker does not skip GitHub Actions CI.

One-time App setup:

1. [Register the dedicated private RBI App](https://github.com/settings/apps/new?name=guileful-charger-rbi-myuzu&description=Publish%20generated%20Dependabot%20RBI%20interfaces&url=https%3A%2F%2Fgithub.com%2FMyuzu%2Fguileful_charger&public=false&webhook_active=false&contents=write&pull_requests=read).
   Keep webhooks disabled. Permissions are repository **Contents: read/write** and
   **Pull requests: read**; metadata read is automatic.
2. Install the App on **only** `Myuzu/guileful_charger`, then generate and download
   its private key from the App settings. No OAuth callback or webhook server is needed.
3. Store its client ID as an Actions repository variable and its key as an Actions
   repository secret (not Dependabot secrets):

   ```bash
   gh variable set RBI_APP_CLIENT_ID --repo Myuzu/guileful_charger --body '<App client ID>'
   gh secret set RBI_APP_PRIVATE_KEY --repo Myuzu/guileful_charger < /path/to/private-key.pem
   ```

Until those values are configured, generation still produces a downloadable artifact,
but publication fails with a setup message when changes are needed. The publisher
workflow becomes active after it is merged into the default branch. Once configured,
ask Dependabot to rebase an existing Bundler PR to exercise the complete flow.
The first verification run can fail for stale committed RBIs; the App's follow-up
commit runs CI again against the refreshed interfaces.

For manual recovery, check out the dependency PR, run `bin/tapioca gems --all` and
`CI=1 bin/tapioca dsl` with a prepared test database, then commit the
generated interfaces and rerun the normal checks. Never execute downloaded artifact
content as Ruby or apply its paths outside the two generated directories.

The publisher uses only Ruby standard libraries and `gh`. Run its regression tests
without Rails or a database with:

```bash
bundle exec ruby bin/test_tooling automation
```

CI runs the Rails suite without coverage instrumentation. Focused tooling specs
live under `test/tooling/` and do not also run in `bin/rspec`. Runtime policy
and Tapioca compiler coverage run in separate Ruby processes with
`bundle exec ruby bin/test_tooling runtime` and `bundle exec ruby bin/test_tooling compiler`.
The compiler specs live outside `spec/` because `tapioca/internal` globally patches
Ruby reflection, signatures, and autoloading. They must not load into the Rails
suite. Each tooling profile requires 100% line coverage of its implementation.
`make test-tooling` runs all three profiles in containers after preparing the test
database; `make check` and `make test-all` include them.

## Deployment and Infrastructure Notes

- `.devcontainer/compose.yaml` starts Rails, PostgreSQL 18.6, and RabbitMQ 4.4.0 for development/test use. The PostgreSQL image extends `postgres:18.6` with the PostgreSQL 18 packages for `pg_partman` and `pg_cron` (verified with versions 5.5.0 and 1.6.8). PostgreSQL 18+ mounts data at `/var/lib/postgresql` rather than `/var/lib/postgresql/data`. `pg_cron` is preloaded with `cron.database_name=guileful_charger_development`; Rails migrations create the extension and schedule outbox maintenance jobs.
- PostgreSQL 18.3 → 18.6 is a minor upgrade: back up the database, stop PostgreSQL, rebuild its image, and restart it with the existing data volume. No dump/restore or volume deletion is required for this upgrade. Run Rails migrations after replacing the image to update installed extension SQL definitions and keep empty outbox partition sets advancing. Extension upgrades are irreversible; restore a backup if a rollback is needed. Review the [18.6 release notes](https://www.postgresql.org/docs/release/18.6/) for additional steps if your installation uses logical-decoding plugins, PGP encryption, GIN indexes, `btree_gist`, or `ltree`.
- The published outbox retains seven days of data and precreates future partitions even during idle periods. This avoids repeated “Attempt to drop final partition” retention warnings when no messages arrive. Partition maintenance continues to run through `pg_cron`; the `pg_partman` background worker is not enabled, so its 5.5.0 default-role change does not affect this setup.
- RabbitMQ enables the bundled `rabbitmq_management`, `rabbitmq_prometheus`, and `rabbitmq_consistent_hash_exchange` plugins, all at version 4.4.0 in the official management image. These plugins upgrade with the broker; no separate plugin downloads are needed. RabbitMQ/Hutch is configured for durable publishing defaults, publisher confirms, manual acknowledgements, low prefetch, quorum consumer queues, dead-letter routing, retry queues with TTL/DLX, and single-active-consumer queue arguments. Per-consumer queue arguments are declared with `consumer_options` blocks.
- The deprecated management metrics collector is disabled in Compose and CI. Monitoring uses Prometheus at `http://localhost:15692/metrics`; the management UI at `http://localhost:15672` retains administration and queue totals, while charts and detailed statistics are disabled. CI enables the same plugins and checks for alarms and deprecated-feature use. See the [management plugin guidance](https://www.rabbitmq.com/docs/management#disable-stats).
- RabbitMQ still logs `Metrics collection disabled in management agent, management only interface started` at warning level when this supported configuration is active; this is a status notice from the management plugin, not deprecated-feature use. The broker has a 60-second shutdown grace period so quorum queues can stop cleanly before Docker sends a forced kill.
- For existing RabbitMQ 4.3 installations, upgrade to 4.3.7 first, enable all stable feature flags, then move to 4.4.0. The [4.4.0 release notes](https://github.com/rabbitmq/rabbitmq-server/releases/tag/v4.4.0) recommend this intermediate release when upgrading Erlang to 28 or later. Before replacing a container, export definitions and take an offline backup of its data volume. Preserve its node name and hostname: quorum queues cannot be restored under a different node name, and the current Compose configuration uses a container-generated hostname. Follow the [upgrade guide](https://www.rabbitmq.com/docs/upgrade) and [backup guide](https://www.rabbitmq.com/docs/backup) for existing data; fresh environments can start directly with 4.4.0.
- Subscription-scoped outbox messages are also mirrored to a consistent-hash exchange by `subscription_id` for shard-oriented processing/inspection; primary Hutch consumers still re-check PostgreSQL state/version because RabbitMQ delivery can be duplicate or out of order.
- `k8s/` contains development-style Kubernetes manifests for single-instance PostgreSQL, RabbitMQ, and Rails deployments.
- `config/deploy.yml` is the generated Kamal-style deployment scaffold and still contains placeholder hosts/image names.
- The repository does not currently include production-grade PostgreSQL HA, RabbitMQ HA, secret management, backup/restore, or disaster-recovery configuration.
