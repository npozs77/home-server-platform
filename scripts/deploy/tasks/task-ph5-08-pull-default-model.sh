#!/bin/bash
# Task: Pull default and additional LLM models (one-time)
# Phase: 5 (Wiki + LLM Platform — Sub-phase B)
# Number: 08
# Prerequisites:
#   - Ollama container running and healthy (Task 9.3 / task-ph5-07)
#   - Internet connectivity for model download
# Parameters:
#   --dry-run: Report planned model pulls without executing
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required (services.env):
#   OLLAMA_DEFAULT_MODEL (default: llama3.2:3b)
# Environment Variables Optional (services.env):
#   OLLAMA_ADDITIONAL_MODELS (default: mistral:7b, space-separated)
# Satisfies: Requirements 7.7, 7.9, 13.1, 13.2, 13.6

set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utilities (absolute paths)
source /opt/homeserver/scripts/operations/utils/output-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Configuration paths
SERVICES_ENV="/opt/homeserver/configs/services.env"

# Source environment files (only if vars not already exported by orchestrator)
if [[ -z "${OLLAMA_DEFAULT_MODEL:-}" ]]; then
    print_info "Loading configuration..."
    if [[ -f "$SERVICES_ENV" ]]; then
        source "$SERVICES_ENV"
    fi
fi

# Defaults
DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-llama3.2:3b}"
ADDITIONAL_MODELS="${OLLAMA_ADDITIONAL_MODELS:-mistral:7b}"

# Validate prerequisites
print_info "Validating prerequisites..."

if ! docker info &> /dev/null; then
    print_error "Docker is not running"
    exit 3
fi

# Check Ollama container is running and healthy
OLLAMA_STATUS=$(docker inspect --format='{{.State.Health.Status}}' ollama 2>/dev/null || echo "not_found")
if [[ "$OLLAMA_STATUS" != "healthy" ]]; then
    print_error "Ollama container is not healthy (status: $OLLAMA_STATUS)"
    print_error "Deploy the LLM stack first (task-ph5-07-deploy-llm-stack.sh)"
    exit 3
fi

# Build list of all models to pull
ALL_MODELS=("$DEFAULT_MODEL")
if [[ -n "$ADDITIONAL_MODELS" ]]; then
    read -ra EXTRA <<< "$ADDITIONAL_MODELS"
    for model in "${EXTRA[@]}"; do
        # Avoid duplicates
        if [[ "$model" != "$DEFAULT_MODEL" ]]; then
            ALL_MODELS+=("$model")
        fi
    done
fi

# Get list of already-pulled models (idempotency)
EXISTING_MODELS=""
if docker exec ollama ollama list &>/dev/null; then
    EXISTING_MODELS=$(docker exec ollama ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')
fi

# Determine which models need pulling
MODELS_TO_PULL=()
MODELS_SKIPPED=()
for model in "${ALL_MODELS[@]}"; do
    if echo "$EXISTING_MODELS" | grep -q "^${model}$"; then
        MODELS_SKIPPED+=("$model")
    else
        MODELS_TO_PULL+=("$model")
    fi
done

print_info "Default model: $DEFAULT_MODEL"
print_info "Additional models: ${ADDITIONAL_MODELS:-none}"
print_info "Total models: ${#ALL_MODELS[@]}"
print_info "Already pulled: ${#MODELS_SKIPPED[@]}"
print_info "To pull: ${#MODELS_TO_PULL[@]}"

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Model pull plan:"
    for model in "${MODELS_SKIPPED[@]}"; do
        print_info "  - $model (already exists — skip)"
    done
    for model in "${MODELS_TO_PULL[@]}"; do
        print_info "  - $model (would pull)"
    done
    if [[ ${#MODELS_TO_PULL[@]} -eq 0 ]]; then
        print_info "[DRY-RUN] All models already pulled — nothing to do"
    fi
else
    # Skip if all models already pulled
    if [[ ${#MODELS_TO_PULL[@]} -eq 0 ]]; then
        print_success "All models already pulled — skipping"
        docker exec ollama ollama list
        print_success "Task complete"
        exit 0
    fi

    # Pull each model
    PULLED=0
    FAILED=0
    for model in "${MODELS_TO_PULL[@]}"; do
        print_info "Pulling model: $model (this may take several minutes)..."
        if docker exec ollama ollama pull "$model"; then
            print_success "Pulled $model"
            PULLED=$((PULLED + 1))
        else
            print_error "Failed to pull $model"
            FAILED=$((FAILED + 1))
        fi
    done

    # Verify models available
    print_info "Verifying available models..."
    docker exec ollama ollama list

    # Summary
    print_info "Pull summary: $PULLED pulled, ${#MODELS_SKIPPED[@]} skipped (already exist), $FAILED failed"

    if [[ $FAILED -gt 0 ]]; then
        print_error "$FAILED model(s) failed to pull — check internet connectivity"
        exit 1
    fi

    print_success "All models pulled successfully"
fi

print_success "Task complete"
exit 0
