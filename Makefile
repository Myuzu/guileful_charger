# Define the Docker Compose file for development/testing services
DOCKER_COMPOSE_FILE := .devcontainer/compose.yaml
RAILS_APP_SERVICE := rails-app

.PHONY: all help docker-build-test docker-compose-up-test docker-compose-down-test db-test-prepare bootstrap test test-all clean-docker-test

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

test-all: docker-build-test docker-compose-up-test db-test-prepare test ## Build, setup, and run all tests
	@echo "All tests completed successfully."

clean-docker-test: ## Remove test Docker images and volumes
	docker-compose -f $(DOCKER_COMPOSE_FILE) down -v --rmi all
	docker rmi guileful_charger_test || true
