ENV_FILE    := .env
ENV_SAMPLE  := .env.sample

DOCKER_COMPOSE := docker compose
COMPOSE_FILE   := docker-compose.yml

-include $(ENV_FILE)
export

PROJECT_NAME := toggle-master

REQUIRES_ENV := \
	docker-up \
	check

REQUIRED_VARS := \
	POSTGRES_USER_AUTH_SERVICE \
	POSTGRES_PASSWORD_AUTH_SERVICE \
	POSTGRES_DB_AUTH_SERVICE \
	PORT_AUTH_SERVICE \
	MASTER_KEY_AUTH_SERVICE \
	POSTGRES_USER_TOGGLE_DB \
	POSTGRES_PASSWORD_TOGGLE_DB \
	POSTGRES_DB_TOGGLE_DB \
	PORT_FLAG_SERVICE \
	PORT_TARGETING_SERVICE \
	PORT_EVALUATION_SERVICE \
	AWS_REGION \
	AWS_SQS_URL \
	AWS_ACCESS_KEY_ID \
	AWS_SECRET_ACCESS_KEY \
	AWS_DYNAMODB_TABLE \
	PORT_ANALYTICS_SERVICE

ifneq ($(filter $(REQUIRES_ENV),$(MAKECMDGOALS)),)
  ifeq ($(wildcard $(ENV_FILE)),)
    $(info Environment file '$(ENV_FILE)' not found. Creating from '$(ENV_SAMPLE)'.)
    $(shell cp $(ENV_SAMPLE) $(ENV_FILE))
  endif

  $(foreach var,$(REQUIRED_VARS),\
    $(if $(value $(var)),,$(error Required environment variable '$(var)' is not set in $(ENV_FILE)))\
  )
endif

.DEFAULT_GOAL := help

.PHONY: \
	help \
	check \
	docker-up \
	docker-down \
	docker-ps \
	kaboom

help:
	@printf "\nUsage: make <target>\n\n"
	@printf "Targets:\n"
	@printf "  %-16s %s\n" "check <svc>"   "Run check script for a service"
	@printf "  %-16s %s\n" "check-all"      "Run all service checks in sequence"
	@printf "  %-16s %s\n" "docker-up"     "Build and start all containers"
	@printf "  %-16s %s\n" "docker-down"   "Stop and remove all containers"
	@printf "  %-16s %s\n" "docker-ps"     "List running containers"
	@printf "  %-16s %s\n" "kaboom"        "Remove containers, volumes, images and orphans"
	@printf "  %-16s %s\n" "localstack-setup" "Setup infrastucture in LocalStack"
	@printf "\n"

check:
	@SERVICE="$(word 2,$(MAKECMDGOALS))"; \
	URL="$(word 3,$(MAKECMDGOALS))"; \
	if [ -z "$$SERVICE" ]; then \
		echo "Usage: make check <service-name> [base_url]"; exit 1; \
	fi; \
	SCRIPT="scripts/check/$$SERVICE.sh"; \
	if [ ! -f "$$SCRIPT" ]; then \
		echo "Check script not found for service '$$SERVICE'."; exit 1; \
	fi; \
	$$SCRIPT $$URL

check-all:
	@./scripts/check/all.sh

docker-up:
	$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) up -d --build

docker-down:
	$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) down

docker-ps:
	$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) ps

kaboom:
	$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) down -v --rmi local --remove-orphans

localstack-setup:
	@echo "Creating SQS queue 'evaluation-events' in LocalStack..."
	@docker exec localstack awslocal sqs create-queue --queue-name evaluation-events || echo "Queue might already exist"
	@echo "Creating DynamoDB table 'analytics-events' in LocalStack..."
	@docker exec localstack awslocal dynamodb create-table \
		--table-name analytics-events \
		--attribute-definitions AttributeName=event_id,AttributeType=S \
		--key-schema AttributeName=event_id,KeyType=HASH \
		--provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 || echo "Table might already exist"

%:
	@:
