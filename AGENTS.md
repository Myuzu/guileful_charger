# Agent instructions for guileful_charger

These instructions apply across the repository. Keep changes focused on the
requested task and preserve unrelated tracked and untracked work.

## Project context and references

Rails API subscription-billing prototype using PostgreSQL, RabbitMQ/Hutch, AASM,
MoneyRails, and dry-rb. Use the Ruby version in [`.ruby-version`](.ruby-version)
and Bundler version in [`Gemfile.lock`](Gemfile.lock).

Read the guide relevant to the change; there is no required full-document tour:

| Work | Reference |
| --- | --- |
| Application boundaries and implementation status | [README](README.md) |
| Setup, services, test prerequisites, and cleanup | [Development](docs/development.md) |
| Retry planning and execution boundaries | [Rebilling](docs/rebilling.md) |
| Sorbet, dry-rb interfaces, and RBI generation | [Type checking](docs/type-checking.md) |
| Dependabot and the trusted RBI publisher | [Dependency automation](docs/dependency-automation.md) |
| Outbox partitions, broker topology, and infrastructure | [Operations](docs/operations.md) |

Rebilling design/roadmap notes describe proposals as well as implemented code.
Check the current guide and source before treating a proposed API as available.

## Setup and commands

Native setup: `bundle install`, then `RAILS_ENV=test bin/rails db:prepare` when
database-backed checks are needed. Use PostgreSQL matching the
[project image](.devcontainer/postgres/Dockerfile), with `pg_partman` available.
Container setup: `make bootstrap`; the Makefile requires a Compose 2+
`docker-compose` command. `make help` lists targets.

| Check | Native command | Container target |
| --- | --- | --- |
| Rails specs | `bin/rspec` | `make test` |
| Automation coverage | `bundle exec ruby bin/test_tooling automation --seed 42` | `make test-tooling` (both profiles) |
| Compiler coverage | `bin/test_tooling compiler` | `make test-tooling` (both profiles) |
| Ruby style | `bin/rubocop` | `make lint` |
| Security | `bin/brakeman --no-pager` | `make security-check` |
| Static types | `bundle exec srb tc` | `make typecheck` |
| Gem RBI drift | `bin/tapioca gems --verify` | `make rbi-verify` (gem and DSL) |
| Rails DSL RBI drift | `CI=1 bin/tapioca dsl --verify` | `make rbi-verify` (gem and DSL) |

Use `bin/rspec spec/models/customer_spec.rb --seed 123` for a focused run, or
`make test RSPEC_ARGS="spec/models/customer_spec.rb --seed 123"` in containers.
`make check` combines specs, tooling coverage, lint, types, and RBI verification;
run security separately. Native Rails specs and DSL verification need a prepared
test database; the two tooling profiles and static type check do not.

Make targets can start/recreate shared services. Inspect existing services before
using them; prefer executing checks in an already prepared container when that
avoids disturbing local work. `make docker-compose-down-test` preserves volumes;
`make clean-docker-test` deletes shared development/test PostgreSQL and RabbitMQ
data volumes and service images. Use destructive cleanup only within an explicitly
authorized cleanup scope.

## Implementation and verification

- Follow [`.rubocop.yml`](.rubocop.yml), Rails naming/autoloading, and nearby
  service/consumer conventions. Keep database/gateway effects outside the pure
  rebilling planner.
- Add meaningful regression tests for executable changes and demonstrate 100%
  coverage of new or changed code. Tooling profiles enforce 100% executable line
  coverage of their [declared implementation files](script/test_coverage_runner.rb); extend the appropriate profile
  when adding tooling code. This does not mean the entire application already has
  measured 100% coverage.
- Keep Tapioca compiler specs in `test/tooling/`, in their separate process.
  Loading `tapioca/internal` in the Rails spec process changes global reflection,
  signatures, and autoloading. Preload tooling dependencies before coverage starts.
- Regenerate RBIs with `bin/tapioca gems` and `CI=1 bin/tapioca dsl` when relevant;
  use the [type-checking guide](docs/type-checking.md) for full regeneration rules.
  Review and commit generated changes rather than hand-editing RBIs.
- Run the focused checks for the changed surface, then any affected CI checks.
  For documentation-only work, validate Markdown, links, and changed examples or
  diagrams. Report commands/results and any unavailable checks accurately; do not
  add unrelated tests or rerun successful suites without a reason.

## Code Review Rules

- **Billing changes:** preserve transactional state/outbox writes, domain locks,
  uniqueness constraints, and subscription-version checks. Duplicate delivery
  must not create duplicate invoice/attempt effects. Broker confirms do not
  guarantee exactly-once gateway charging.
- **Outbox/schema changes:** preserve unpublished messages during retention.
  Migrations own partition and extension configuration; a schema-only dump cannot
  replace `pg_partman` maintenance metadata.
- **Sorbet boot changes:** test actual signature mismatches in fresh and preloaded
  production processes. A skipped policy or an environment-variable assertion
  alone cannot prove production call behavior.
- **RBI automation changes:** preserve the unprivileged generation/trusted
  publisher boundary. Publishing must use default-branch code, validate artifacts
  as data, and restrict writes to approved generated paths. Keep action pins and
  explicit least-privilege workflow permissions.

## Commits and pull requests

- Use a task branch. Fetch `origin/main` before starting a new branch from main;
  continue an existing task on its branch. Review the diff and stage only task files.
- Use descriptive conventional commit/PR titles such as `fix: ...` or `docs: ...`.
  Create/push PRs within the user's requested scope; merge only when instructed.
- Describe the resulting behavior, motivation, validation, and material limits.
  Use headings, tables, and checklists where they improve scanning; keep review
  history and abandoned approaches out of the description.
- **Apply appropriate existing repository labels to every PR and verify them.**
  Use `documentation` for Markdown-only changes, `bug` for fixes, and topic labels
  matching actual scope. Reserve `dependencies` for dependency updates.
- Update affected guides when behavior changes, and remove task-created temporary
  artifacts before finishing. Leave unrelated local work intact.

## Maintaining these instructions

Keep durable repository rules here and detailed explanations in the linked guides.
Add a nested `AGENTS.md` only when a directory needs distinct instructions. Update
commands when [the Makefile](Makefile) or [CI](.github/workflows/ci.yml) changes.
This structure follows the official [AGENTS.md guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
and [focused-instructions guidance](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra).
