#!/usr/bin/env bash
# Tests validate-configs.sh against real fixture trees: a full copy of this
# repo's actual etc/+usr/ config (must pass), then deliberately-broken
# copies of it — one real corruption per validated class — each must be
# caught. Corruptions mirror bug classes already found and fixed live in
# this repo (see AGENTS.md "Audit-verified known issues", e.g. the missing
# comma before GOTO that broke udevadm verify on two wheel-perms rules).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-configs.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

FAILED=0
check() {
    local desc="$1" expect="$2" dir="$3"
    local out rc
    out=$("$VALIDATOR" "$dir" 2>&1)
    rc=$?
    if [[ "$expect" == "pass" && $rc -eq 0 ]] || [[ "$expect" == "fail" && $rc -ne 0 ]]; then
        echo "  PASS: $desc"
    else
        echo "  FAIL: $desc (expected $expect, got rc=$rc)"
        echo "$out" | sed 's/^/    /'
        FAILED=1
    fi
}

echo "Test 1: the real repo's own config tree passes validation..."
check "real repo tree" pass "$REPO_ROOT"

echo "Test 2: a broken sudoers fragment is caught..."
d="$TMPDIR/t2"; cp -r "$REPO_ROOT" "$d"
echo 'this is not valid sudoers syntax @#$%' >> "$d/etc/sudoers.d/wheel"
check "corrupted sudoers.d/wheel" fail "$d"

echo "Test 3: a broken udev rule (missing comma before GOTO) is caught..."
d="$TMPDIR/t3"; cp -r "$REPO_ROOT" "$d"
# Same real bug class already fixed in this repo once (see AGENTS.md):
# a GOTO clause with no comma separating it from the prior match.
printf 'KERNEL=="sda", SUBSYSTEM=="block" GOTO="nonexistent_label"\n' >> "$d/usr/lib/udev/rules.d/70-controllers.rules"
check "corrupted udev rule (missing comma before GOTO)" fail "$d"

echo "Test 4: the known-accepted 40-hpet-permissions.rules warning is NOT flagged..."
check "unmodified 40-hpet-permissions.rules stays exempt" pass "$REPO_ROOT"

echo "Test 5: a NEW real error in 40-hpet-permissions.rules (not just the known warning) is still caught..."
d="$TMPDIR/t5"; cp -r "$REPO_ROOT" "$d"
printf 'this is not a valid udev rule line at all\n' >> "$d/usr/lib/udev/rules.d/40-hpet-permissions.rules"
check "40-hpet-permissions.rules with an unrelated new error" fail "$d"

echo "Test 6: invalid JS syntax in the polkit rules file is caught..."
d="$TMPDIR/t6"; cp -r "$REPO_ROOT" "$d"
printf '\nfunction broken( {\n' >> "$d/usr/share/polkit-1/rules.d/99-shani.rules"
check "corrupted polkit rules (invalid JS)" fail "$d"

echo "Test 7: a malformed systemd conf.d drop-in is caught..."
d="$TMPDIR/t7"; cp -r "$REPO_ROOT" "$d"
printf 'this is not Key=Value or a [Section] header\n' >> "$d/usr/lib/systemd/system.conf.d/limits.conf"
check "corrupted systemd conf.d drop-in" fail "$d"

echo "Test 8: a nonexistent repo root is rejected..."
check "nonexistent path" fail "/nonexistent-repo-root-$$"

if [[ $FAILED -eq 0 ]]; then
    echo "All validator tests passed!"
    exit 0
else
    echo "Some validator tests FAILED"
    exit 1
fi
