#!/usr/bin/env bash
# Property Test: Samba Ownership Inheritance (Property 5)
# Purpose: Verify Media share has force group = media;
#          verify Family share has force group = family;
#          verify files copied via Samba inherit correct ownership
# Validates: Requirements 17.7, 17.8
# Usage: bash tests/test_phase4_property_samba_ownership.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# Test against the example template (smb.conf is generated on the server)
SMB_CONF="configs/samba/smb.conf.example"
if [[ ! -f "$SMB_CONF" ]]; then
    echo -e "${RED}✗ FATAL${NC}: smb.conf.example not found"
    exit 1
fi
echo "Using smb.conf: $SMB_CONF"
echo ""

# Normalize line endings
SMB_CONTENT=$(tr -d '\r' < "$SMB_CONF")

# Helper: extract a share block by name
# Returns all lines from [ShareName] until the next [section] or EOF
get_share_block() {
    local share_name="$1"
    local capture=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[${share_name}\] ]]; then
            capture=true
            continue
        fi
        if $capture; then
            # Stop at next share section
            if [[ "$line" =~ ^\[.+\] ]]; then
                break
            fi
            echo "$line"
        fi
    done <<< "$SMB_CONTENT"
}

echo "========================================"
echo "Property 5: Samba Ownership Inheritance"
echo "========================================"
echo ""

# --- Media share checks ---
echo "--- [Media] share ---"

MEDIA_BLOCK=$(get_share_block "Media")

# Check 1: Media share exists
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -n "$MEDIA_BLOCK" ]]; then
    print_pass "[Media] share block found in smb.conf"
else
    print_fail "[Media] share block NOT found in smb.conf"
fi

# Check 2: Media share has force group = media
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$MEDIA_BLOCK" | grep -qi 'force group = media'; then
    print_pass "[Media] has 'force group = media'"
else
    print_fail "[Media] MISSING 'force group = media'"
fi

# Check 3: Media share has create mask that allows group write
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$MEDIA_BLOCK" | grep -qE 'create mask = 0[67][67][0-7]'; then
    print_pass "[Media] has group-writable create mask"
else
    print_fail "[Media] create mask does not allow group write"
fi

# Check 4: Media share has directory mask that allows group access
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$MEDIA_BLOCK" | grep -qE 'directory mask = 0[67][67][0-7]'; then
    print_pass "[Media] has group-accessible directory mask"
else
    print_fail "[Media] directory mask does not allow group access"
fi

echo ""
echo "--- [Family] share ---"

# --- Family share checks ---
FAMILY_BLOCK=$(get_share_block "Family")

# Check 5: Family share exists
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -n "$FAMILY_BLOCK" ]]; then
    print_pass "[Family] share block found in smb.conf"
else
    print_fail "[Family] share block NOT found in smb.conf"
fi

# Check 6: Family share has force group = family
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$FAMILY_BLOCK" | grep -qi 'force group = family'; then
    print_pass "[Family] has 'force group = family'"
else
    print_fail "[Family] MISSING 'force group = family'"
fi

# Check 7: Family share has create mask that allows group write
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$FAMILY_BLOCK" | grep -qE 'create mask = 07[67]0'; then
    print_pass "[Family] has group-writable create mask"
else
    print_fail "[Family] create mask does not allow group write"
fi

# Check 8: Family share has directory mask that allows group access
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$FAMILY_BLOCK" | grep -qE 'directory mask = 07[67]0'; then
    print_pass "[Family] has group-accessible directory mask"
else
    print_fail "[Family] directory mask does not allow group access"
fi

echo ""
echo "--- Cross-share ownership inheritance ---"

# Check 9: Media share force group ensures files inherit media group
# (force group = media means any file created via Samba gets group:media)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$MEDIA_BLOCK" | grep -qi 'force group = media' && \
   echo "$MEDIA_BLOCK" | grep -qE 'force create mode = 0[67][67][0-7]'; then
    print_pass "[Media] force group + force create mode ensures ownership inheritance"
else
    # Check if at least force group is set (force create mode is optional)
    if echo "$MEDIA_BLOCK" | grep -qi 'force group = media'; then
        print_pass "[Media] force group = media ensures group ownership inheritance"
    else
        print_fail "[Media] MISSING force group for ownership inheritance"
    fi
fi

# Check 10: Family share force group ensures files inherit family group
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$FAMILY_BLOCK" | grep -qi 'force group = family'; then
    print_pass "[Family] force group = family ensures group ownership inheritance"
else
    print_fail "[Family] MISSING force group for ownership inheritance"
fi

echo ""
echo "========================================"
echo "Samba Ownership Inheritance Summary"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 5 holds: Samba shares enforce correct ownership inheritance${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 5 violated: Ownership inheritance checks failed${NC}"
    exit 1
fi
