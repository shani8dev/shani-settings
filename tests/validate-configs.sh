#!/usr/bin/env bash
#
# validate-configs.sh — run every shipped config's own real validator
# (visudo, testparm, udevadm, node) against the actual files in this repo's
# etc/ and usr/ trees. See AGENTS.md "Rule: syntax-check every config with
# its own real validator, don't eyeball it".
#
# This intentionally does NOT parse an invented /etc/shani/shani.conf
# format — this repo ships no such file (confirmed: `find etc usr -iname
# '*shani.conf*'` matches only etc/environment.d/90-shani.conf and
# usr/lib/sysctl.d/99-sysctl-shani.conf, neither INI-sectioned). An earlier
# version of this script validated a fictional [network]/[security]/
# [services] config that doesn't correspond to anything this repo actually
# packages — replaced 2026-09-18 after that was caught live (the CI job
# calling it was passing on a format nobody ships, not on this repo's real
# config surface).
#
# Usage: validate-configs.sh [repo-root]   (defaults to this script's repo)
set -uo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if [[ ! -d "$REPO_ROOT" ]]; then
    echo "ERROR: repo root not found: $REPO_ROOT" >&2
    exit 1
fi

ERRORS=0
FAIL() { echo "ERROR: $*" >&2; ERRORS=$((ERRORS + 1)); }
WARN() { echo "WARN: $*" >&2; }

# ── sudoers.d fragments ──────────────────────────────────────────────────
if compgen -G "$REPO_ROOT/etc/sudoers.d/*" >/dev/null 2>&1; then
    for f in "$REPO_ROOT"/etc/sudoers.d/*; do
        [[ -f "$f" ]] || continue
        if ! visudo -c -f "$f" >/dev/null 2>&1; then
            FAIL "visudo rejected $f"
        fi
    done
fi

# ── Samba ─────────────────────────────────────────────────────────────────
if [[ -f "$REPO_ROOT/etc/samba/smb.conf" ]]; then
    if command -v testparm >/dev/null 2>&1; then
        if ! testparm -s "$REPO_ROOT/etc/samba/smb.conf" >/dev/null 2>&1; then
            FAIL "testparm rejected $REPO_ROOT/etc/samba/smb.conf"
        fi
    else
        WARN "testparm not installed, skipping etc/samba/smb.conf (install samba-common-bin)"
    fi
fi

# ── udev rules ────────────────────────────────────────────────────────────
# 40-hpet-permissions.rules is a known, deliberately-accepted exception (see
# AGENTS.md "Audit-verified known issues"): it references the "realtime"
# group, which is only created by shani-multimedia's .install and doesn't
# exist on profiles that don't depend on it (kiosk) — harmless no-op there,
# investigated and left as-is. udevadm still reports this file as failed, so
# exempt ONLY that exact known warning; any other output from this file
# (including a genuinely new problem in it) still fails the check.
if compgen -G "$REPO_ROOT/usr/lib/udev/rules.d/*.rules" >/dev/null 2>&1; then
    for f in "$REPO_ROOT"/usr/lib/udev/rules.d/*.rules; do
        [[ -f "$f" ]] || continue
        out=$(udevadm verify "$f" 2>&1)
        rc=$?
        if [[ $rc -ne 0 ]]; then
            if [[ "$(basename "$f")" == "40-hpet-permissions.rules" ]]; then
                unexpected=$(echo "$out" | grep -v "Unknown group 'realtime', ignoring\." \
                    | grep -v "udev rules check failed\." \
                    | grep -v "udev rules files have been checked\." \
                    | grep -v "^[[:space:]]*Success:" \
                    | grep -v "^[[:space:]]*Fail:" \
                    | grep -v "^[[:space:]]*$")
                [[ -n "$unexpected" ]] && FAIL "udevadm verify failed on $f with unexpected output: $unexpected"
            else
                FAIL "udevadm verify failed on $f: $out"
            fi
        fi
    done
fi

# ── polkit rules (JS syntax) ──────────────────────────────────────────────
# node --check requires a .js extension to recognize the file as CommonJS;
# copy to a temp .js path rather than renaming the real file.
if compgen -G "$REPO_ROOT/usr/share/polkit-1/rules.d/*.rules" >/dev/null 2>&1; then
    if command -v node >/dev/null 2>&1; then
        for f in "$REPO_ROOT"/usr/share/polkit-1/rules.d/*.rules; do
            [[ -f "$f" ]] || continue
            tmpjs=$(mktemp --suffix=.js)
            cp "$f" "$tmpjs"
            if ! node --check "$tmpjs" 2>/dev/null; then
                FAIL "node --check rejected $f (invalid JS syntax)"
            fi
            rm -f "$tmpjs"
        done
    else
        WARN "node not installed, skipping polkit rules JS syntax check"
    fi
fi

# ── systemd manager/journald drop-ins ────────────────────────────────────
# No .service/.timer units ship in this repo (confirmed:
# `find usr/lib/systemd -name '*.service' -o -name '*.timer'` is empty), so
# systemd-analyze verify has nothing to check here — only manager/journald
# config drop-ins (*.conf.d/*.conf), which that tool doesn't validate. At
# minimum confirm each one parses as a well-formed [Section]/Key=Value file.
if compgen -G "$REPO_ROOT/usr/lib/systemd/*.conf.d/*.conf" >/dev/null 2>&1; then
    for f in "$REPO_ROOT"/usr/lib/systemd/*.conf.d/*.conf; do
        [[ -f "$f" ]] || continue
        if awk '
            /^[[:space:]]*(#|;|$)/ { next }
            /^\[[A-Za-z0-9]+\]$/ { next }
            /^[A-Za-z][A-Za-z0-9]*[[:space:]]*=/ { next }
            { print "line " NR ": " $0; bad=1 }
            END { exit bad }
        ' "$f"; then
            :
        else
            FAIL "$f has a line that isn't a comment, [Section], or Key=Value"
        fi
    done
fi

if [[ $ERRORS -eq 0 ]]; then
    echo "All config validators passed ($REPO_ROOT)"
    exit 0
else
    echo "$ERRORS validator failure(s)"
    exit 1
fi
