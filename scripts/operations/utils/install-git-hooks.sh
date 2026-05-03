#!/bin/bash
set -euo pipefail
# Install local git hooks to enforce branch workflow
# Usage: bash scripts/operations/utils/install-git-hooks.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HOOKS_DIR="${REPO_ROOT}/.git/hooks"

# Pre-commit: block commits on main + shellcheck staged .sh files
cat > "${HOOKS_DIR}/pre-commit" << 'EOF'
#!/bin/bash
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
if [[ "$BRANCH" == "main" ]]; then
    echo "ERROR: Direct commits to main are not allowed."
    echo "Create a feature branch: git checkout -b feat/my-change"
    echo "Bypass with: git commit --no-verify"
    exit 1
fi

# Shellcheck: lint staged .sh files
if command -v shellcheck &>/dev/null; then
    STAGED_SH=$(git diff --cached --name-only --diff-filter=ACM -- '*.sh')
    if [[ -n "$STAGED_SH" ]]; then
        FAILED=0
        for f in $STAGED_SH; do
            if ! shellcheck -S warning "$f"; then
                FAILED=1
            fi
        done
        if [[ "$FAILED" -eq 1 ]]; then
            echo ""
            echo "ERROR: shellcheck found issues in staged .sh files."
            echo "Fix them or bypass with: git commit --no-verify"
            exit 1
        fi
    fi
else
    echo "WARNING: shellcheck not installed — skipping lint (brew install shellcheck)"
fi
EOF
chmod +x "${HOOKS_DIR}/pre-commit"

# Pre-push: block pushes to main
cat > "${HOOKS_DIR}/pre-push" << 'EOF'
#!/bin/bash
while read local_ref local_sha remote_ref remote_sha; do
    if [[ "$remote_ref" == "refs/heads/main" ]]; then
        echo "ERROR: Direct pushes to main are not allowed."
        echo "Push your feature branch and create a PR on GitHub."
        echo "Bypass with: git push --no-verify"
        exit 1
    fi
done
EOF
chmod +x "${HOOKS_DIR}/pre-push"

echo "Git hooks installed: pre-commit (main protection + shellcheck) + pre-push (main protection)"
echo "Bypass when needed: --no-verify"
