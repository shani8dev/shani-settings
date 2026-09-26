#!/usr/bin/env bash
#
# check-pam-drift.sh — verify our etc/pam.d/system-auth is still in sync with
# the pambase file it forks.
#
# Why this exists: shani-settings ships its own /etc/pam.d/system-auth so that
# `auth sufficient pam_u2f.so` is actually loaded (no stock PAM stack referenced
# pam_u2f, so a FIDO2/U2F key was installed and inert). That makes our file a
# fork of a distro-owned one, and the fork drifts silently — pambase's own
# upgrade does not touch our file, so a pambase bump that changes the login
# stack leaves the two disagreeing with nothing to notice. That is not
# cosmetic: this file governs the auth stack for every graphical login and for
# sudo/su, so a missed upstream change is a silently divergent auth policy.
#
# What it compares: the significant (non-comment, non-blank) lines, with our one
# added pam_u2f line removed. Anything left over is upstream drift we have not
# carried over.
#
# Usage: bash tests/check-pam-drift.sh [path/to/our/system-auth]
#   Defaults to etc/pam.d/system-auth in this repo.
# Requires pambase installed (provides /etc/pam.d/system-auth to compare against).

set -uo pipefail

OURS="${1:-etc/pam.d/system-auth}"
THEIRS="/etc/pam.d/system-auth"

if [[ ! -f "$OURS" ]]; then
    echo "FAIL: $OURS not found" >&2
    exit 1
fi
if [[ ! -f "$THEIRS" ]]; then
    # Server/minimal images may not carry pambase; say so rather than pass silently.
    echo "SKIP: $THEIRS is absent (pambase not installed) — cannot compare." >&2
    exit 0
fi

# Significant lines only: drop comments and blanks, squeeze internal runs of
# whitespace, so pure reformatting upstream is not reported as drift.
norm() {
    sed -e 's/#.*$//' -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//' "$1" \
        | grep -v '^$'
}

# Our one intentional addition, removed before comparing.
theirs=$(norm "$THEIRS")
ours=$(norm "$OURS" | grep -v 'pam_u2f\.so')

if [[ "$ours" == "$theirs" ]]; then
    echo "OK: system-auth matches pambase apart from the pam_u2f line."
    exit 0
fi

echo "FAIL: our pam.d/system-auth has drifted from pambase's." >&2
echo "  ours:   $OURS" >&2
echo "  theirs: $THEIRS" >&2
echo >&2
echo "Only in ours (we changed it, or upstream removed it):" >&2
comm -23 <(printf '%s\n' "$ours" | sort) <(printf '%s\n' "$theirs" | sort) | sed 's/^/    /' >&2
echo "Only in pambase (upstream drift not carried over):" >&2
comm -13 <(printf '%s\n' "$ours" | sort) <(printf '%s\n' "$theirs" | sort) | sed 's/^/    /' >&2
echo >&2
echo "Re-diff and carry upstream changes over by hand — do not just re-pin." >&2
exit 1
