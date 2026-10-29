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

- Use `# typed: strict` for new or newly adopted application Ruby code and
  handwritten RBIs. Do not introduce `typed: true` as an adoption target.
  Existing `typed: true` files are legacy migration work; generated RBIs retain
  their generator's sigils. Require strict files through `Sorbet/StrictSigil` in
  [`.rubocop.yml`](.rubocop.yml), removing promoted files from the legacy
  `Sorbet/TrueSigil` list. Static strictness does not change runtime checking policy.
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

## Task and PR lifecycle

1. **Select the task.** For project-backed work, use the existing issue and its
   linked project. When asked for the next task, consider project order, priority,
   and unresolved dependencies. The typing backlog is
   [Sorbet inc.](https://github.com/users/Myuzu/projects/6). Read the project's
   actual status options rather than assuming field IDs or names.
2. **Start from main.** Fetch `origin/main` and create a fresh branch for each new
   task; continue ongoing work on its existing branch. Move the linked issue to
   **In progress** before implementation. Preserve unrelated local work.
3. **Implement with TDD.** Add meaningful failing behavior/type tests first, then
   implement at `typed: strict` using the verification rules above. Preserve
   existing behavior when adopting types. Research official documentation when
   library details are uncertain. For documentation-only work, use the Markdown,
   link, and example checks above.
4. **Prepare the PR.** Review the diff, stage only task files, and use descriptive
   conventional commit/PR titles such as `feat: ...`, `fix: ...`, or `docs: ...`.
   Open/push within the requested scope and link the issue with `Closes #...` when
   appropriate. Explain the resulting behavior, motivation, validation, and limits
   using headings, tables, and checklists where useful. Omit review history and
   abandoned approaches. **Apply and verify existing repository labels**:
   `documentation` for Markdown-only work, `bug` for fixes, relevant topic labels,
   and `dependencies` only for dependency updates. Move the issue to **In review**
   when the PR is ready.
5. **Get independent review before merge.** Spawn a review subagent with a fresh
   context (`fork_turns: "none"`). Provide the task brief, repository path, exact
   base/head commits, constraints, and test setup; do not pass conversation history
   or implementation reasoning. Keep the reviewer read-only. Verify actionable
   findings, avoid duplicate threads, and post a `COMMENT` review through `gh`
   against the reviewed commit. If there are no findings, post a summary with
   checks and limits. Address confirmed findings within the authorized
   implementation scope and re-review changed code if the head changes. Pure
   review requests do not authorize source edits.
6. **Merge only on explicit instruction.** Recheck the reviewed head, mergeability,
   and required CI checks. Follow the repository's merge strategy and pin the
   reviewed head with `--match-head-commit` when using `gh pr merge`.
7. **Complete the task.** Verify the PR is merged and the linked issue is closed,
   then move its project item to **Done** (the completed column on the typing
   board). Verify the saved status before reporting completion. Update affected
   guides and remove task-created temporary artifacts; preserve unrelated work.

## Maintaining these instructions

Keep durable repository rules here and detailed explanations in the linked guides.
Add a nested `AGENTS.md` only when a directory needs distinct instructions. Update
commands when [the Makefile](Makefile) or [CI](.github/workflows/ci.yml) changes.
This structure follows the official [AGENTS.md guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
and [focused-instructions guidance](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra).
