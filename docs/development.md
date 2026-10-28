# Development

[← README](../README.md) · [Type checking](type-checking.md) · [Operations](operations.md)

## Container workflow

Install Docker, a `docker-compose` command, and Make. The
[Compose file](../.devcontainer/compose.yaml) shares the working tree with a Rails
container and starts PostgreSQL and RabbitMQ.

```bash
make bootstrap
make test
make check
```

| Target | Effect |
| --- | --- |
| `make help` | List targets and descriptions; also the default `make` action |
| `make docker-compose-up-test` | Start shared development/test services |
| `make db-test-prepare` | Start services and prepare `guileful_charger_test` |
| `make test` | Prepare the test database and run Rails specs |
| `make test-tooling` | Run automation and compiler profiles in isolated Ruby processes |
| `make lint` / `make security-check` | Run RuboCop / Brakeman |
| `make typecheck` | Run Sorbet without a database connection |
| `make rbi-verify` | Prepare test DB, verify gem RBIs, then verify Rails DSL RBIs |
| `make check` | Specs, tooling coverage, lint, typecheck, and RBI verification |
| `make test-all` | Build the test image, start services, prepare DB, run Rails/tooling specs |

`make check` does not include Brakeman; run `make security-check` too. Source:
[Makefile](../Makefile).

```bash
make test RSPEC_ARGS="spec/models/customer_spec.rb --seed 123"
make lint RUBOCOP_ARGS="app/services"
make security-check BRAKEMAN_ARGS="--no-pager"
```

### Running the prototype

Compose leaves Rails running `sleep infinity`. After installing gems, prepare the
development database and start each desired process explicitly:

```bash
docker-compose -f .devcontainer/compose.yaml exec rails-app bin/rails db:prepare
docker-compose -f .devcontainer/compose.yaml exec rails-app bin/rails server -b 0.0.0.0
```

Run Hutch in another terminal:

```bash
docker-compose -f .devcontainer/compose.yaml exec rails-app bundle exec hutch
```

Open a container shell for a manual billing pass:

```bash
docker-compose -f .devcontainer/compose.yaml exec rails-app bash
```

Then invoke the scheduler and publisher:

```bash
bin/rails runner 'PaymentScheduler.new(PaymentSchedulerConfig.new).run!'
bin/rails runner 'OutboxPublisherService.call'
```

Run the publisher again after consumers produce new outbox rows. There is no
checked-in recurring invocation for these services;
[`config/recurring.yml`](../config/recurring.yml) contains commented examples only.
These commands demonstrate individual passes rather than a continuously running
billing system.

The [Dev Container configuration](../.devcontainer/devcontainer.json) forwards
port `3000`. Compose itself does not publish that Rails port; use editor port
forwarding or configure a local port mapping to reach `/up` from the host.
RabbitMQ administration and Prometheus ports are published by Compose.

## Native Ruby workflow

Use the versions pinned in [`.ruby-version`](../.ruby-version) and
[`Gemfile.lock`](../Gemfile.lock): Ruby **4.0.9**, Bundler **4.0.23**.

```bash
gem install bundler -v 4.0.23
bundle install
RAILS_ENV=test bin/rails db:prepare
bin/rspec
bin/rubocop
bin/brakeman --no-pager
```

The test database needs PostgreSQL 18 with `pg_partman` available for migrations
to create. Use a connection matching [`config/database.yml`](../config/database.yml),
or set `DATABASE_URL`. `pg_cron` enables scheduled maintenance in the database
selected by `cron.database_name`; migrations skip that setup when it is
unavailable, unconfigured, or points to another database. Compose preloads it for
the development database, so test migrations skip cron scheduling. Native test
boot avoids connecting Hutch; full CI also starts RabbitMQ.
Non-test application boot uses [`config/hutch.yaml`](../config/hutch.yaml), whose
broker hostname defaults to the Compose service `rabbitmq`.

## Test boundaries

| Suite | Command | Requirements |
| --- | --- | --- |
| Rails behavior and signature building | `bin/rspec` | Prepared test PostgreSQL |
| Automation / boot coverage | `bundle exec ruby bin/test_tooling automation --seed 42` | Gems; no database service required |
| Custom Tapioca compiler coverage | `bin/test_tooling compiler` | Gems; no Rails boot or database service required |
| Rails DSL drift | `CI=1 bin/tapioca dsl --verify` | Prepared test PostgreSQL |

Both tooling profiles require **100% line coverage of their listed implementation
files**. Dependencies load before coverage begins. The launcher preserves an
outer coverage session, and entrypoint scenarios use child processes to avoid
Ruby resetting coverage on repeated `load`.

> [!IMPORTANT]
> Keep Tapioca compiler specs outside `spec/`. Loading `tapioca/internal` changes
> Ruby reflection, signatures, and autoloading globally, so compiler tests run in
> a separate process from the Rails suite.

CI runs the Rails suite without coverage instrumentation. Independent matrix jobs
run lint, security, static checking, and the two tooling profiles. DSL verification
runs after DB preparation; its failure does not hide the subsequent spec results.

## Cleanup

Choose the scope explicitly:

| Command | Removes | Keeps |
| --- | --- | --- |
| `make docker-compose-down-test` | Compose containers/network | Data volumes and images |
| `docker image prune -a` | Images unused by any container, across the machine | Containers and volumes |
| `make clean-docker-test` | Compose containers, volumes, and service/test images | Files in the working tree |

> [!WARNING]
> Development and test share the same Compose project. `make clean-docker-test`
> deletes its PostgreSQL and RabbitMQ volumes, including development data.
> Use the non-destructive stop target when you only need to shut services down.
