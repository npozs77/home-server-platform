#!/bin/bash
# Install git hooks and gitleaks config for this repository
# Run once after cloning: bash scripts/setup-hooks.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_DIR="${REPO_ROOT}/.git/hooks"

# Pre-commit: gitleaks PII/secret scanning
cat > "${HOOK_DIR}/pre-commit" << 'EOF'
#!/bin/bash
# Pre-commit hook: run gitleaks to catch PII and secrets before commit
# Skip: git commit --no-verify

if ! command -v gitleaks &>/dev/null; then
    echo "⚠ gitleaks not installed — skipping PII check (brew install gitleaks)"
    exit 0
fi

if [[ ! -f .gitleaks.toml ]]; then
    echo "⚠ .gitleaks.toml not found — run scripts/setup-hooks.sh to configure PII rules"
    exit 0
fi

gitleaks protect --staged --config .gitleaks.toml --verbose
EOF
chmod +x "${HOOK_DIR}/pre-commit"
echo "✓ Pre-commit hook installed"

# Generate .gitleaks.toml if missing
if [[ ! -f "${REPO_ROOT}/.gitleaks.toml" ]]; then
    echo ""
    echo "Configure PII detection rules (leave blank to skip a pattern):"
    read -p "  Real domain to detect (e.g. example.net): " domain
    read -p "  Real username to detect (e.g. johndoe): " username
    read -p "  Real git username to detect (e.g. jdoe42): " gituser

    cat > "${REPO_ROOT}/.gitleaks.toml" << TOML
[extend]
useDefault = true
TOML

    [[ -n "$domain" ]] && cat >> "${REPO_ROOT}/.gitleaks.toml" << TOML

[[rules]]
id = "real-domain"
description = "Hardcoded real domain"
regex = '''${domain//./\\.}'''
tags = ["pii", "domain"]
TOML

    [[ -n "$username" ]] && cat >> "${REPO_ROOT}/.gitleaks.toml" << TOML

[[rules]]
id = "real-username"
description = "Hardcoded real username"
regex = '''${username}'''
tags = ["pii", "username"]
TOML

    [[ -n "$gituser" ]] && cat >> "${REPO_ROOT}/.gitleaks.toml" << TOML

[[rules]]
id = "real-git-username"
description = "Hardcoded real git username"
regex = '''${gituser}'''
tags = ["pii", "username"]
TOML

    cat >> "${REPO_ROOT}/.gitleaks.toml" << 'TOML'

[allowlist]
paths = [
    '''\.env$''',
    '''\.env\..*$''',
    '''OLD/''',
    '''\.git/''',
]
TOML
    echo "✓ .gitleaks.toml generated (gitignored — local only)"
else
    echo "✓ .gitleaks.toml already exists"
fi

echo ""
echo "Requires: gitleaks (brew install gitleaks / https://github.com/gitleaks/gitleaks)"
