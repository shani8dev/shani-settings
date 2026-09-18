#!/usr/bin/env bash
#
# check-checksums.sh — verify shani-settings repo files match the
# source=/sha256sums=() arrays in the sibling shani-pkgbuilds PKGBUILD.
#
# Unlike shani-keyring (whose PKGBUILD lists per-file sources with real
# hashes), shani-settings is packaged as a single release tarball with
# sha256sums=('SKIP') — content authenticity is delegated to the pinned
# _commit the tarball is built from, not to a checksum list. In that
# mode nothing can be checksummed here, so this script prints a notice
# and exits 0. If the PKGBUILD is ever converted to per-file sources
# with real hashes, the same comparison path as shani-keyring's
# check-checksums.sh activates automatically.
#
# Usage:
#   ./tests/check-checksums.sh [path/to/PKGBUILD]
#
# Exit codes:
#   0 — all real hashes match (or all entries are SKIP)
#   1 — one or more real hashes mismatch (or PKGBUILD not found / unparseable)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Default PKGBUILD location: sibling shani-pkgbuilds repo
PKGBUILD="${1:-${REPO_ROOT}/../shani-pkgbuilds/shani-settings/PKGBUILD}"

if [[ ! -f "$PKGBUILD" ]]; then
    echo "ERROR: PKGBUILD not found at: $PKGBUILD" >&2
    echo "Usage: $0 [path/to/PKGBUILD]" >&2
    exit 1
fi

echo "Checking checksums against: $PKGBUILD"
echo

# --- Parse the source=() array to get filenames ---
# PKGBUILD source entries may be single- or double-quoted and may use the
# "name::url" form (filename is the part before "::", not the URL's
# basename — e.g. "shani-settings.tar.gz::https://.../archive/${_commit}.tar.gz"
# must yield "shani-settings.tar.gz"). Handle all three shapes.
mapfile -t SOURCE_URLS < <(
    awk '/^source=/{f=1} f{print} f&&/\)/{f=0}' "$PKGBUILD" \
        | grep -oE "'[^']+'|\"[^\"]+\"" \
        | tr -d "'\"" \
        | while IFS= read -r entry; do
            entry="${entry%%::*}"
            basename "$entry"
        done
)

# --- Parse the sha256sums=() array, keeping SKIP entries verbatim ---
mapfile -t EXPECTED_HASHES < <(
    awk '/^sha256sums=/{f=1} f{print} f&&/\)/{f=0}' "$PKGBUILD" \
        | grep -oE "'[^']+'|\"[^\"]+\"" \
        | tr -d "'\""
)

# --- Validate we got matching counts ---
if [[ ${#SOURCE_URLS[@]} -eq 0 ]]; then
    echo "ERROR: could not parse source=() array from PKGBUILD" >&2
    exit 1
fi

if [[ ${#EXPECTED_HASHES[@]} -eq 0 ]]; then
    echo "ERROR: could not parse sha256sums=() array from PKGBUILD" >&2
    exit 1
fi

if [[ ${#SOURCE_URLS[@]} -ne ${#EXPECTED_HASHES[@]} ]]; then
    echo "ERROR: source=() (${#SOURCE_URLS[@]} entries) and sha256sums=()" \
         "(${#EXPECTED_HASHES[@]} entries) length mismatch" >&2
    exit 1
fi

# --- Count SKIP entries; short-circuit if every hash is SKIP ---
SKIP_COUNT=0
for h in "${EXPECTED_HASHES[@]}"; do
    if [[ "$h" == "SKIP" ]]; then
        SKIP_COUNT=$((SKIP_COUNT + 1))
    fi
done

if [[ "$SKIP_COUNT" -eq "${#EXPECTED_HASHES[@]}" ]]; then
    echo "All ${#EXPECTED_HASHES[@]} sha256sums=() entries are SKIP."
    echo
    echo "shani-settings is packaged as a release tarball (source=('...tar.gz::https://"
    echo "github.com/shani8dev/shani-settings/archive/\${_commit}.tar.gz')) with content"
    echo "authenticity delegated to the pinned _commit, so there are no per-file"
    echo "checksums to compare against. Skipping checksum comparison."
    echo
    echo "NOTE: the tarball is pinned at _commit from the PKGBUILD; if the repo"
    echo "has commits newer than that pin, the published package is stale until"
    echo "the PKGBUILD _commit is bumped. That bump is a packaging decision and"
    echo "intentionally does not fail this check."
    exit 0
fi

echo "$SKIP_COUNT of ${#EXPECTED_HASHES[@]} entries are SKIP; comparing the rest."
echo

# --- Compare every non-SKIP entry against the repo file ---
MISMATCH=0
for i in "${!SOURCE_URLS[@]}"; do
    filename="${SOURCE_URLS[$i]}"
    expected="${EXPECTED_HASHES[$i]}"

    if [[ "$expected" == "SKIP" ]]; then
        echo "SKIP:    $filename (no checksum in PKGBUILD)"
        continue
    fi

    filepath="${REPO_ROOT}/${filename}"

    if [[ ! -f "$filepath" ]]; then
        echo "MISSING: $filename (file not found in repo)" >&2
        MISMATCH=1
        continue
    fi

    actual="$(sha256sum "$filepath" | awk '{print $1}')"

    if [[ "$actual" == "$expected" ]]; then
        echo "OK:      $filename  $actual"
    else
        echo "MISMATCH: $filename" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        MISMATCH=1
    fi
done

echo
if [[ $MISMATCH -eq 0 ]]; then
    echo "All non-SKIP checksums match."
    exit 0
else
    echo "FAIL: checksum mismatch detected — PKGBUILD is stale." >&2
    exit 1
fi