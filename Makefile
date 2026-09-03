# Homeserver — operator front-door.
# `make` (no target) prints help. Targets mirror the exact commands used by CI
# and by day-to-day operations, so you don't have to remember them.
#
# Location-aware: server-directed targets (deploy, validate, server-status)
# adapt to WHERE `make` runs — locally on the server, or over SSH from a dev
# machine. See "location awareness" below.

# --- configurable variables ---
# SERVER is the SSH alias defined in your ~/.ssh/config (NOT an IP/hostname —
# ssh resolves the real HostName/User/IdentityFile from that alias). It is a
# local, machine-specific nickname, so it is not PII and is safe to default here.
#
# Precedence (highest first):
#   1. command-line argument   →  make deploy SERVER=other-host
#   2. environment variable    →  SERVER=other-host make deploy
#   3. the default below       →  homeserver
# To change the default permanently, edit this line manually. There is no env
# file for this on the dev machine — the SSH alias lives in ~/.ssh/config.
SERVER ?= homeserver
BRANCH ?= main
PHASE ?=
REMOTE ?= origin
SERVER_DIR ?= /opt/homeserver

SHELL := /bin/bash
.DEFAULT_GOAL := help

# --- location awareness ---
# The server is the checkout at $(SERVER_DIR). If this Makefile lives there, we
# are ON the server → run server commands locally in $(CURDIR). Otherwise we are
# on a dev machine → prefix with ssh and cd into $(SERVER_DIR). This makes the
# same `make deploy` work from either place, and prevents a server-directed
# command from running against a local (non-server) checkout by mistake.
ON_SERVER := $(shell [ "$(CURDIR)" = "$(SERVER_DIR)" ] && echo 1 || echo 0)
ifeq ($(ON_SERVER),1)
  WHERE = server (local, $(SERVER_DIR))
else
  WHERE = dev machine (ssh $(SERVER))
endif

# srun = run a command in the server checkout, from either location.
# On the server: `bash -c 'cd DIR && CMD'`.
# On a dev machine: `ssh SERVER 'cd DIR && CMD'` — the whole remote command is
# ONE quoted argument, so nothing (e.g. the part after &&) leaks to the local
# shell. Usage:  $(call srun,<command>)
ifeq ($(ON_SERVER),1)
  srun = bash -c 'cd $(SERVER_DIR) && $(1)'
else
  srun = ssh $(SERVER) 'cd $(SERVER_DIR) && $(1)'
endif

# --- help ---
.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Running from: $(WHERE)"
	@echo "Variables: SERVER=$(SERVER) BRANCH=$(BRANCH) REMOTE=$(REMOTE) SERVER_DIR=$(SERVER_DIR) [PHASE=N]"

# ============================================================================
# Quality gates — run in the repo, from anywhere (mirror .github/workflows/ci.yml)
# ============================================================================
.PHONY: quality
quality: test lint governance secrets ## Run all local CI gates (test + lint + governance + secrets)
	@echo "✓ quality: all local CI gates passed"

.PHONY: test
test: ## Run CI-safe test suites (tests/run-all.sh --ci)
	bash tests/run-all.sh --ci

.PHONY: test-all
test-all: ## Run ALL test suites, including non-CI-safe ones
	bash tests/run-all.sh

.PHONY: lint
lint: ## Shellcheck all scripts/ at -S warning (as CI does)
	find scripts/ -name '*.sh' -print0 | xargs -0 shellcheck -S warning

.PHONY: governance
governance: ## Validate governance (script sizes, patterns, executable bits)
	bash scripts/operations/validate-governance.sh

.PHONY: secrets
secrets: ## Scan for committed secrets with gitleaks (skips gracefully if not installed)
	@command -v gitleaks >/dev/null 2>&1 \
		&& gitleaks detect --source . --config .gitleaks.toml --no-banner \
		|| echo "⚠ gitleaks not installed locally — CI runs it; skipping"

.PHONY: mirror-check
mirror-check: ## Dry-run the public-mirror filter locally and prove no private content leaks
	@bash scripts/operations/check-mirror-privacy.sh

# ============================================================================
# Server operations — location-aware (local on server, ssh from dev machine)
# ============================================================================
.PHONY: deploy
deploy: ## Converge the server to origin/$(BRANCH) (fetch + reset --hard)
	$(call srun,bash scripts/operations/utils/deploy-update.sh $(BRANCH))

.PHONY: deploy-force
deploy-force: ## Same as deploy, but approve discarding server-side local changes
	$(call srun,bash scripts/operations/utils/deploy-update.sh $(BRANCH) --force)

.PHONY: server-status
server-status: ## Show the server's current branch, HEAD, and working-tree status
	$(call srun,git status -sb)

.PHONY: validate
validate: ## Run server phase validation (all phases, or one with PHASE=N)
	$(call srun,sudo bash scripts/operations/validate-all.sh $(if $(PHASE),--phase $(PHASE),))
