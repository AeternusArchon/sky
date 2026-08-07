.DEFAULT_GOAL := help
SHELL := /bin/bash
COMPOSE := docker compose

.PHONY: help up down restart logs ps build health psql backup restore-test hostcheck fmt

help: ## Show this help
	@echo ""
	@echo "  SKY — operations"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""

up: ## Start the stack
	$(COMPOSE) up -d
	@echo "→ waiting for health..."
	@sleep 6
	@$(MAKE) --no-print-directory health

down: ## Stop the stack (data volume survives)
	$(COMPOSE) down

restart: ## Restart everything
	$(COMPOSE) restart

build: ## Rebuild images
	$(COMPOSE) build --pull

logs: ## Follow all logs
	$(COMPOSE) logs -f --tail=100

ps: ## Container status
	$(COMPOSE) ps

health: ## Gateway health as JSON
	@curl -fsS localhost:8080/health | (command -v jq >/dev/null && jq || cat)

hostcheck: ## Host health — CPU temp, SMART, RAM, disk, uptime
	@bash ops/health/healthcheck.sh | (command -v jq >/dev/null && jq || cat)

psql: ## Postgres shell
	$(COMPOSE) exec postgres psql -U $${POSTGRES_USER:-sky} -d $${POSTGRES_DB:-sky}

backup: ## Run a backup now
	@bash ops/backup/backup.sh

restore-test: ## RESTORE DRILL — verify backups into a throwaway DB. Run monthly.
	@bash ops/backup/restore.sh

fmt: ## Format Python
	@command -v ruff >/dev/null && ruff format services/ || echo "ruff not installed — skipping"
