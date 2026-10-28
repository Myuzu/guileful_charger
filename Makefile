# Define the Docker Compose file for development/testing services
DOCKER_COMPOSE_FILE := .devcontainer/compose.yaml
RAILS_APP_SERVICE := rails-app

.PHONY: all help docker-build-test docker-compose-up-test docker-compose-down-test db-test-prepare bootstrap test test-tooling lint typecheck rbi-verify security-check test-all check clean-docker-test

.DEFAULT_GOAL := help

# help: Display this help message
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

docker-build-test: ## Build the Docker image for the test environment
	docker build -f .devcontainer/Dockerfile -t guileful_charger_test .

docker-compose-up-test: ## Bring up all Docker services (Rails app, PostgreSQL, RabbitMQ) for testing
	docker-compose -f $(DOCKER_COMPOSE_FILE) up -d

docker-compose-down-test: ## Bring down the Docker services
	docker-compose -f $(DOCKER_COMPOSE_FILE) down

bootstrap: docker-compose-up-test ## Fetch Ruby dependencies inside the Docker container
	docker-compose -f $(DOCKER_COMPOSE_FILE) exec $(RAILS_APP_SERVICE) bundle install

db-test-prepare: docker-compose-up-test ## Prepare the test database inside the container
	docker-compose -f $(DOCKER_COMPOSE_FILE) exec $(RAILS_APP_SERVICE) bin/rails db:prepare RAILS_ENV=test

test: db-test-prepare ## Run RSpec tests inside the Docker container. Usage: make test RSPEC_ARGS="spec/models/customer_spec.rb:123 --seed 123"
	docker-compose -f $(DOCKER_COMPOSE_FILE) exec $(RAILS_APP_SERVICE) bin/rspec $(RSPEC_ARGS)

test-tooling: docker-compose-up-test ## Check tooling coverage in isolated Ruby processes (no database needed)
	docker-compose -f $(DOCKER_COMPOSE_FILE) exec -T $(RAILS_APP_SERVICE) bundle exec ruby bin/test_tooling automation
	docker-compose -f $(DOCKER_COMPOSE_FILE) exec -T -e CI=1 $(RAILS_APP_SERVICE) bundle exec ruby bin/test_tooling compiler

lint: docker-compose-up-test ## Run RuboCop inside the Docker container. Usage: make lint RUBOCOP_ARGS="app/services"
	docker-compose -f $(DOCKER_COMPOSE_FILE) exec $(RAILS_APP_SERVICE) bin/rubocop $(RUBOCOP_ARGS)

security-check: docker-compose-up-test ## Run Brakeman inside the Docker container. Usage: make security-check BRAKEMAN_ARGS="--no-pager"
	docker-compose -f $(DOCKER_COMPOSE_FILE) exec $(RAILS_APP_SERVICE) bin/brakeman $(BRAKEMAN_ARGS)

typecheck: docker-compose-up-test ## Run Sorbet inside the Rails container (no database needed)
	docker-compose -f $(DOCKER_COMPOSE_FILE) exec -T $(RAILS_APP_SERVICE) bundle exec srb tc

rbi-verify: db-test-prepare ## Verify committed gem and DSL interfaces after preparing the test database
	docker-compose -f $(DOCKER_COMPOSE_FILE) exec -T $(RAILS_APP_SERVICE) bin/tapioca gems --verify
	docker-compose -f $(DOCKER_COMPOSE_FILE) exec -T -e CI=1 $(RAILS_APP_SERVICE) bin/tapioca dsl --verify

test-all: docker-build-test docker-compose-up-test db-test-prepare test test-tooling ## Build, setup, and run all tests
	@echo "All tests completed successfully."

check: test test-tooling lint typecheck rbi-verify ## Run tests, tooling coverage, linting, type checking, and interface verification
	@echo "Checks completed successfully."

clean-docker-test: ## Remove test Docker images and volumes
	docker-compose -f $(DOCKER_COMPOSE_FILE) down -v --rmi all
	docker rmi guileful_charger_test || true
