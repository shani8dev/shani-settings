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
# Guarded like Tests 9-11: validate-configs.sh WARNs and skips this block when
# `node` is absent, so an unguarded "fail" assertion demands a failure the
# validator deliberately does not produce. This exact case was left unguarded
# and failed for that reason on a host without node (found 2026-10-10, when
# Tests 10-11 were added with guards and Test 6 was the one control left
# reporting a false failure).
if command -v node >/dev/null 2>&1; then
    d="$TMPDIR/t6"; cp -r "$REPO_ROOT" "$d"
    printf '\nfunction broken( {\n' >> "$d/usr/share/polkit-1/rules.d/99-shani.rules"
    check "corrupted polkit rules (invalid JS)" fail "$d"
else
    echo "Test 6: SKIPPED (no node on PATH; the polkit block would be skipped, not exercised)"
fi

echo "Test 7: a malformed systemd conf.d drop-in is caught..."
d="$TMPDIR/t7"; cp -r "$REPO_ROOT" "$d"
printf 'this is not Key=Value or a [Section] header\n' >> "$d/usr/lib/systemd/system.conf.d/limits.conf"
check "corrupted systemd conf.d drop-in" fail "$d"

echo "Test 8: a nonexistent repo root is rejected..."
check "nonexistent path" fail "/nonexistent-repo-root-$$"

# Test 9 covers the sshd drop-in class, but only when a real sshd is on PATH:
# validate-configs.sh WARNs and skips that block without one, so asserting
# "fail" here without sshd would demand a failure the validator deliberately
# does not produce, and asserting "pass" would assert nothing was checked.
# Skipping explicitly is the honest outcome - a control that cannot fail is not
# a control.
if command -v sshd >/dev/null 2>&1 && command -v ssh-keygen >/dev/null 2>&1; then
    echo "Test 9: a broken sshd drop-in is caught..."
    d="$TMPDIR/t9"; cp -r "$REPO_ROOT" "$d"
    printf 'ClientAliveInterval notanumber\n' >> "$d/etc/ssh/sshd_config.d/00-shani-hardening.conf"
    check "corrupted sshd_config.d drop-in" fail "$d"
else
    echo "Test 9: SKIPPED (no sshd/ssh-keygen on PATH; the sshd block would be skipped, not exercised)"
fi

# Test 10 covers the audit rules, on the same terms as Test 9: validate-configs.sh
# WARNs and skips the block when auditctl is absent, so asserting "fail" without
# it would demand a failure the validator deliberately does not produce.
#
# `augenrules --check` is NOT the validator here and is not used as a control:
# measured on a real Arch tree (audit 4.x) it returns 0 for a file containing
# nothing but the text "this is not a rule". A control that cannot fail is not a
# control, so this uses the same discriminator validate-configs.sh uses — an
# unparseable rule makes auditctl exit non-zero with no output, whereas a rule
# that parses reaches the kernel and fails with "Error sending add rule data
# request". That is precisely why the check works on hosts with no CAP_AUDIT_CONTROL.
if command -v auditctl >/dev/null 2>&1; then
    echo "Test 10: an unparseable audit rule is caught..."
    d="$TMPDIR/t10"; cp -r "$REPO_ROOT" "$d"
    # A bad permission filter (-p zzz) is a real audit-syntax error, not a
    # semantic one, so it is caught by the parser anywhere it runs.
    printf -- '-w /etc/passwd -p zzz -k identity\n' >> "$d/etc/audit/rules.d/10-shani-base.rules"
    check "unparseable audit rule (-p zzz)" fail "$d"

    echo "Test 11: a line that is not a rule at all is caught..."
    d="$TMPDIR/t11"; cp -r "$REPO_ROOT" "$d"
    printf 'this is not an audit rule\n' >> "$d/etc/audit/rules.d/10-shani-base.rules"
    check "garbage line in audit rules" fail "$d"
else
    echo "Test 10-11: SKIPPED (no auditctl on PATH; the audit block would be skipped, not exercised)"
fi

if [[ $FAILED -eq 0 ]]; then
    echo "All validator tests passed!"
    exit 0
else
    echo "Some validator tests FAILED"
    exit 1
fi
