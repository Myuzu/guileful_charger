# Agent Guidelines for guileful_charger

This document outlines the essential commands and code style guidelines for agents working within this repository.

## Build/Lint/Test Commands

*   **Install Dependencies**: `bundle install`
*   **Run All Tests**: `make test`
*   **Run a Single Test**: `make test spec/models/customer_spec.rb:123 --seed 123` (e.g., `make test spec/models/customer_spec.rb`)
*   **Run Linter**: `bin/rubocop`
*   **Run Security Scan**: `bin/brakeman`
*   **Build Test Docker Image**: `make docker-build-test`
*   **Start Test Services**: `make docker-compose-up-test`
*   **Prepare Test Database**: `make db-test-prepare`
*   **Fetch Ruby Dependencies (Docker)**: `make bootstrap`
*   **Run All Tests (Docker)**: `make test`
*   **Full Test Workflow (Docker)**: `make test-all`
*   **Clean Test Docker Environment**: `make clean-docker-test`

## Language Server Protocol (LSP)

This project uses the Ruby LSP for enhanced development experience. Ensure your editor is configured to use `ruby-lsp` for features like autocompletion, go-to-definition, and diagnostics.

## Code Style Guidelines

This project adheres to the [RuboCop Rails Omakase](https://github.com/rails/rubocop-rails-omakase/) style guide, with additional performance and RSpec cops.

*   **Formatting**: Enforced by RuboCop. Run `bin/rubocop` to check and auto-correct (if applicable).
*   **Naming Conventions**: Follow Ruby and Rails conventions.
*   **Error Handling**: Standard Ruby error handling practices.
*   **Imports/Requires**: Managed by Bundler and Rails autoloading.
