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
# `visudo -c -f` on a *fragment* validates the file as a standalone sudoers
# file, which is what a drop-in is meant to be.
#
# Unlike the sections below, this one used to have no `command -v visudo` guard:
# on a machine without the `sudo` package the invocation failed with 127 and
# `FAIL "visudo rejected ..."` fired for every fragment — a false failure that
# reads as a syntax error in this repo. Found 2026-10-10 by running the script
# in an Arch container that had the audit but not the sudo package: the script
# reported 4 "visudo rejected" errors on files visudo parses fine, because the
# binary did not exist. Every other section here already guarded for its tool
# (testparm, sshd, ssh-keygen, node); this was the one that didn't, and CI never
# caught it because ubuntu-latest ships sudo.
if compgen -G "$REPO_ROOT/etc/sudoers.d/*" >/dev/null 2>&1; then
    if ! command -v visudo >/dev/null 2>&1; then
        WARN "visudo not installed, skipping etc/sudoers.d/* (install sudo)"
    else
        for f in "$REPO_ROOT"/etc/sudoers.d/*; do
            [[ -f "$f" ]] || continue
            if ! visudo -c -f "$f" >/dev/null 2>&1; then
                FAIL "visudo rejected $f"
            fi
        done
    fi
fi

# ── SSH server drop-ins ────────────────────────────────────────────────────
# sshd has no per-file syntax check: `sshd -t -f <dropin>` cannot parse a drop-in
# on its own, because the file is only ever read through the Include in
# sshd_config, and the whole point of a drop-in is that it composes with the
# main config and with Arch's own 99-archlinux.conf. So the real check is a
# synthetic main config that Includes this repo's drop-in directory plus Arch's,
# which is exactly what the installed system does.
#
# `sshd -t` needs at least one readable host key or it exits before parsing
# ("no hostkeys available -- exiting"), which would make this check pass for
# the wrong reason. A throwaway ed25519 key is generated for the check and
# thrown away with the temp dir; it is never a usable server key.
if compgen -G "$REPO_ROOT/etc/ssh/sshd_config.d/*.conf" >/dev/null 2>&1; then
    if ! command -v sshd >/dev/null 2>&1; then
        WARN "sshd not installed, skipping etc/ssh/sshd_config.d/*.conf (install openssh)"
    elif ! command -v ssh-keygen >/dev/null 2>&1; then
        WARN "ssh-keygen not installed, skipping etc/ssh/sshd_config.d/*.conf (install openssh)"
    else
        sshd_tmp=$(mktemp -d)
        # Arch's shipped 99-archlinux.conf, so the check also proves this repo's
        # drop-ins compose with it rather than only being valid in isolation.
        # Sourced from the installed openssh package when present so it tracks
        # upstream; skipped (with a warning) if it isn't.
        arch_sshd_conf=""
        for cand in /etc/ssh/sshd_config.d/99-archlinux.conf; do
            [[ -f "$cand" ]] && { arch_sshd_conf="$cand"; break; }
        done
        cp "$REPO_ROOT"/etc/ssh/sshd_config.d/*.conf "$sshd_tmp"/
        if [[ -n "$arch_sshd_conf" ]]; then
            cp "$arch_sshd_conf" "$sshd_tmp"/
        else
            WARN "Arch's 99-archlinux.conf not found; sshd drop-ins checked without it"
        fi
        {
            echo "Include $sshd_tmp/*.conf"
            echo "HostKey $sshd_tmp/throwaway_hostkey"
        } > "$sshd_tmp/main_config"
        if ! ssh-keygen -q -t ed25519 -f "$sshd_tmp/throwaway_hostkey" -N '' -C validate-configs >/dev/null 2>&1; then
            FAIL "could not generate a throwaway host key to validate etc/ssh/sshd_config.d/*.conf"
        elif out=$(sshd -t -f "$sshd_tmp/main_config" 2>&1); then
            :
        else
            FAIL "sshd rejected etc/ssh/sshd_config.d/*.conf: $out"
        fi
        rm -rf "$sshd_tmp"
    fi
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
                # systemd <= ~255: "Unknown group 'realtime', ignoring."
                # systemd >= 256 (Arch, what ShaniOS builds on):
                #   "Failed to resolve group 'realtime', ignoring: Unknown group"
                unexpected=$(echo "$out" | grep -v -E "Unknown group 'realtime', ignoring\.|Failed to resolve group 'realtime', ignoring: Unknown group" \
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

# ── audit rules ───────────────────────────────────────────────────────────
# `augenrules --check` is NOT usable here and is not used: measured on a real
# Arch tree (audit 4.x), it returns 0 for a file containing the literal text
# "this is not a rule" and for "-w /etc/passwd -p zzz -k identity". It reports
# only whether the rules have changed since the last load, so it is a check
# that cannot fail — the failure mode AGENTS.md warns about.
#
# `auditctl -R` is the real parser, and it does discriminate even where the
# kernel refuses the load (no CAP_AUDIT_CONTROL, or audit compiled out — which
# is the case in a normal build container):
#   * a rule that PARSES reaches the netlink call and prints
#     "Error sending add rule data request (Operation not permitted)"
#   * a rule that FAILS to parse exits 1 with no output at all
# So "no output and non-zero" is a real syntax error, and the EPERM wording is
# the signature of a valid rule this environment simply cannot load.
#
# The audit *directives* (-b buffer, -f failure mode, -D, -e) are shaped
# differently and are validated structurally: `auditctl -R` on a lone `-b 8192`
# also exits 1 with no output, which would make this section report the two
# pre-existing directive lines in this very file as failures on every run — a
# permanently red check, which is as useless as a permanently green one.
if compgen -G "$REPO_ROOT/etc/audit/rules.d/*.rules" >/dev/null 2>&1; then
    if ! command -v auditctl >/dev/null 2>&1; then
        WARN "auditctl not installed, skipping etc/audit/rules.d/*.rules (install audit)"
    else
        for f in "$REPO_ROOT"/etc/audit/rules.d/*.rules; do
            [[ -f "$f" ]] || continue
            lineno=0
            while IFS= read -r line || [[ -n "$line" ]]; do
                lineno=$((lineno + 1))
                # Comments and blank lines are not rules.
                case "$line" in ""|\#*) continue ;; esac
                # Directives: -b <number>, -f <number>, -e <1|2>, -D, -r/-C freq.
                if [[ "$line" =~ ^-[bD](\ |-$) ]] || [[ "$line" =~ ^-[fe]\ [0-9]+$ ]]; then
                    continue
                fi
                printf '%s\n' "$line" > "$REPO_ROOT/.audit-one-check.tmp"
                out=$(auditctl -R "$REPO_ROOT/.audit-one-check.tmp" 2>&1)
                if echo "$out" | grep -q "Error sending add rule data request"; then
                    :   # parsed fine; the kernel refused, which is not our problem here
                elif [[ -z "$out" ]]; then
                    FAIL "auditctl rejected $f line $lineno (unparseable rule): $line"
                else
                    FAIL "auditctl rejected $f line $lineno: $out"
                fi
            done < "$f"
            rm -f "$REPO_ROOT/.audit-one-check.tmp"
        done
    fi
fi

if [[ $ERRORS -eq 0 ]]; then
    echo "All config validators passed ($REPO_ROOT)"
    exit 0
else
    echo "$ERRORS validator failure(s)"
    exit 1
fi
