#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-/etc/shani/shani.conf}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

ERRORS=0

# Check for required sections
for section in network security services; do
    if ! grep -q "^\[$section\]" "$CONFIG_FILE"; then
        echo "ERROR: Missing required section [$section] in $CONFIG_FILE" >&2
        ERRORS=$((ERRORS + 1))
    fi
done

# Validate numeric values are within expected ranges
# Check memory_limit is a positive integer
if grep -q "memory_limit" "$CONFIG_FILE"; then
    mem_val=$(grep "memory_limit" "$CONFIG_FILE" | grep -oP '\d+')
    if [[ -n "$mem_val" && "$mem_val" -lt 1 ]]; then
        echo "ERROR: memory_limit must be a positive integer" >&2
        ERRORS=$((ERRORS + 1))
    fi
fi

# Validate timeout_seconds is a positive integer
if grep -q "timeout_seconds" "$CONFIG_FILE"; then
    timeout_val=$(grep "timeout_seconds" "$CONFIG_FILE" | grep -oP '\d+')
    if [[ -n "$timeout_val" && "$timeout_val" -lt 1 ]]; then
        echo "ERROR: timeout_seconds must be a positive integer" >&2
        ERRORS=$((ERRORS + 1))
    fi
fi

if [[ $ERRORS -eq 0 ]]; then
    echo "Config validation passed: $CONFIG_FILE"
    exit 0
else
    echo "Config validation failed with $ERRORS error(s)" >&2
    exit 1
fi
