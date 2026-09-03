#!/bin/bash
set -euo pipefail
# Mirror Privacy Check — locally prove the public mirror leaks no private content.
# Purpose: replicate .github/workflows/mirror-public.yml's strip + verification
#          gate in a throwaway clone, so you can confirm BEFORE merging to main
#          that no private markers survive the history rewrite.
# Usage: bash scripts/operations/check-mirror-privacy.sh [branch]
#   branch — branch to simulate the mirror from (default: current branch)
# Exit Codes: 0=clean (no leak), 1=private content would leak / prerequisite missing

SCRIPT_NAME="check-mirror-privacy"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BRANCH="${1:-$(git -C "$REPO_ROOT" symbolic-ref --short HEAD 2>/dev/null || echo main)}"
REDACTIONS="${REPO_ROOT}/.github/mirror-redactions.txt"

# Private markers the mirror must never publish (mirror gate uses the same set).
MARKERS='ff[-_]tool|family[-_]financ|REDACTED'

if ! command -v git-filter-repo &>/dev/null && ! git filter-repo --version &>/dev/null 2>&1; then
    echo "ERROR: git-filter-repo not installed (pip install git-filter-repo)" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SIM="${WORK}/mirror-sim"

echo "[${SCRIPT_NAME}] cloning ${BRANCH} into a throwaway repo..."
git clone -q --branch "$BRANCH" "$REPO_ROOT" "$SIM"
cp "$REDACTIONS" "${WORK}/redactions.txt"
cd "$SIM"

echo "[${SCRIPT_NAME}] running the mirror strip (paths + glob + replace-text)..."
git filter-repo --invert-paths \
    --path .kiro/ --path input/ --path private/ --path .gitleaks.toml --path .github/ \
    --path-glob '*REDACTED*' \
    --replace-text "${WORK}/redactions.txt" \
    --force >/dev/null

echo "[${SCRIPT_NAME}] verifying no private markers survive across ALL history..."
# shellcheck disable=SC2046  # intentional: rev-list must word-split into args
if git grep -nIiE "$MARKERS" $(git rev-list --all) -- . 2>/dev/null; then
    echo "✗ LEAK: private content would reach the public mirror (see matches above)" >&2
    exit 1
fi

COMMITS="$(git rev-list --all | wc -l | tr -d ' ')"
echo "✓ clean: no private markers across all ${COMMITS} filtered commits"
