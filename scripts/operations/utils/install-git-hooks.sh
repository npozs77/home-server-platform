#!/bin/bash
set -euo pipefail
# Install local git hooks to enforce branch workflow
# Usage: bash scripts/operations/utils/install-git-hooks.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HOOKS_DIR="${REPO_ROOT}/.git/hooks"

# Pre-commit: block commits on main
cat > "${HOOKS_DIR}/pre-commit" << 'EOF'
#!/bin/bash
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
if [[ "$BRANCH" == "main" ]]; then
    echo "ERROR: Direct commits to main are not allowed."
    echo "Create a feature branch: git checkout -b feat/my-change"
    echo "Bypass with: git commit --no-verify"
    exit 1
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

echo "Git hooks installed: pre-commit + pre-push (main branch protection)"
echo "Bypass when needed: --no-verify"
