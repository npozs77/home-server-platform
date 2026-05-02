#!/bin/bash
# Install git hooks and gitleaks config for this repository
# Run once after cloning: bash scripts/setup-hooks.sh
# Non-interactive: bash scripts/setup-hooks.sh --domain example.net --username johndoe --gituser jdoe42

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_DIR="${REPO_ROOT}/.git/hooks"
DOMAIN="" USERNAME="" GITUSER=""

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain) DOMAIN="$2"; shift 2 ;;
        --username) USERNAME="$2"; shift 2 ;;
        --gituser) GITUSER="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Pre-commit hook
cat > "${HOOK_DIR}/pre-commit" << 'EOF'
#!/bin/bash
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
    # Interactive mode if no args provided
    if [[ -z "$DOMAIN" && -z "$USERNAME" && -z "$GITUSER" ]]; then
        echo ""
        echo "Configure PII detection rules (leave blank to skip):"
        read -p "  Real domain (e.g. example.net): " DOMAIN
        read -p "  Real username (e.g. johndoe): " USERNAME
        read -p "  Real git username (e.g. jdoe42): " GITUSER
    fi

    cat > "${REPO_ROOT}/.gitleaks.toml" << TOML
[extend]
useDefault = true
TOML

    [[ -n "$DOMAIN" ]] && cat >> "${REPO_ROOT}/.gitleaks.toml" << TOML

[[rules]]
id = "real-domain"
description = "Hardcoded real domain"
regex = '''${DOMAIN//./\\.}'''
tags = ["pii", "domain"]
TOML

    [[ -n "$USERNAME" ]] && cat >> "${REPO_ROOT}/.gitleaks.toml" << TOML

[[rules]]
id = "real-username"
description = "Hardcoded real username"
regex = '''${USERNAME}'''
tags = ["pii", "username"]
TOML

    [[ -n "$GITUSER" ]] && cat >> "${REPO_ROOT}/.gitleaks.toml" << TOML

[[rules]]
id = "real-git-username"
description = "Hardcoded real git username"
regex = '''${GITUSER}'''
tags = ["pii", "username"]
TOML

    cat >> "${REPO_ROOT}/.gitleaks.toml" << 'TOML'

[allowlist]
paths = [
    '''\.env$''',
    '''\.env\..*$''',
    '''OLD/''',
    '''\.git/''',
    '''\.kiro/''',
]
TOML
    echo "✓ .gitleaks.toml generated (gitignored — local only)"
else
    echo "✓ .gitleaks.toml already exists"
fi

echo ""
echo "Done. Requires: gitleaks (brew install gitleaks / https://github.com/gitleaks/gitleaks)"
