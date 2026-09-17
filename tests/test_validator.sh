#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-configs.sh"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Test 1: Valid config passes
cat > "$TMPDIR/valid.conf" << 'CONF'
[network]
hostname = shani

[security]
encryption = true

[services]
enabled = ssh
CONF

echo "Test 1: Valid config passes validation..."
if "$VALIDATOR" "$TMPDIR/valid.conf"; then
    echo "  PASS"
else
    echo "  FAIL"
    exit 1
fi

# Test 2: Missing sections fail
cat > "$TMPDIR/invalid.conf" << 'CONF'
[network]
hostname = shani
CONF

echo "Test 2: Missing sections fail validation..."
if ! "$VALIDATOR" "$TMPDIR/invalid.conf" 2>/dev/null; then
    echo "  PASS"
else
    echo "  FAIL"
    exit 1
fi

# Test 3: Bad numeric values fail
cat > "$TMPDIR/badvalues.conf" << 'CONF'
[network]
hostname = shani

[security]
encryption = true

[services]
enabled = ssh
memory_limit = 0
CONF

echo "Test 3: Bad numeric values fail validation..."
if ! "$VALIDATOR" "$TMPDIR/badvalues.conf" 2>/dev/null; then
    echo "  PASS"
else
    echo "  FAIL"
    exit 1
fi

# Test 4: Nonexistent file fails
echo "Test 4: Nonexistent file fails..."
if ! "$VALIDATOR" "/nonexistent.conf" 2>/dev/null; then
    echo "  PASS"
else
    echo "  FAIL"
    exit 1
fi

echo "All validator tests passed!"
