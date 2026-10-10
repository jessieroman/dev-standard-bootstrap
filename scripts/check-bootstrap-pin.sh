#!/bin/sh
# Fail closed when the SHA-pinned curl one-liner in README.md no longer
# serves the same install.sh as dev-standard-bootstrap's main branch.
#
# The documented one-liner pins a commit SHA on purpose: an already-shared
# URL must not change what it serves. The cost of that choice is a manual
# bump, and nothing otherwise reports the day the pin goes stale. This
# guard reports it.
#
# A network failure is not a pin violation: no reachable upstream means no
# evidence of divergence, so the script skips (exit 0) rather than block an
# offline commit. Only a successful fetch of BOTH blobs can fail this.
#
# This script ships as template payload, so it also runs in downstream
# consumer repos whose READMEs carry no pinned URL at all. That is not a
# violation either: zero matches means there is no pin to guard, so the
# script skips (exit 0) instead of blocking every consumer README commit.
#
# README_FILE, REPO_URL and MAIN_SHA override the file checked, the raw base
# URL fetched, and the resolved main revision, so the divergence failure path
# is testable without upstream.
set -eu

# Namespace coupling: override REPO_URL/GIT_URL when the repo moves off
# jessieroman/*.
README_FILE="${README_FILE:-README.md}"
REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/jessieroman/dev-standard-bootstrap}"
GIT_URL="${GIT_URL:-https://github.com/jessieroman/dev-standard-bootstrap.git}"
repo=$(basename "$GIT_URL" .git)
case $repo in
'' | *[!A-Za-z0-9._-]*)
  echo "check-bootstrap-pin: unsafe repository name in GIT_URL: $repo" >&2
  exit 1
  ;;
esac

fix=no
[ "${1:-}" = "--fix" ] && fix=yes

if [ ! -f "$README_FILE" ]; then
  echo "check-bootstrap-pin: no such file: $README_FILE" >&2
  exit 1
fi

shas=$(
  grep -o "$repo/[0-9a-f]\{40\}/install\.sh" "$README_FILE" |
    cut -d/ -f2 | sort -u
)
count=$(printf '%s' "$shas" | grep -c . || true)

if [ "$count" -eq 0 ]; then
  # Fail closed when the README mentions $repo but no
  # URL is SHA-pinned: a pin rewritten to a mutable ref (main, a tag)
  # must not pass as "nothing to guard". Skip only on total absence,
  # which is the consumer-README case this script ships into.
  if grep -q "$repo" "$README_FILE"; then
    echo "check-bootstrap-pin: $README_FILE mentions $repo but pins no 40-hex install.sh URL" >&2
    echo "check-bootstrap-pin: expected $REPO_URL/<40-char-sha>/install.sh" >&2
    exit 1
  fi
  echo "check-bootstrap-pin: $README_FILE has no $repo install.sh URL — skipping pin check"
  exit 0
fi
if [ "$count" -gt 1 ]; then
  echo "check-bootstrap-pin: $README_FILE: $count distinct pinned SHAs, expected 1:" >&2
  echo "$shas" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "check-bootstrap-pin: curl not installed — skipping pin check"
  exit 0
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# raw.githubusercontent.com caches a branch ref for minutes, so fetching
# .../main/install.sh can serve a stale blob long after a push. Resolve main
# to a commit SHA first: a SHA URL is immutable and never stale.
main_sha="${MAIN_SHA:-$(git ls-remote "$GIT_URL" main 2>/dev/null | cut -f1)}"
case $main_sha in
*[!0-9a-f]* | "") # never interpolate an unvalidated value into sed below
  echo "check-bootstrap-pin: could not resolve main — skipping pin check"
  exit 0
  ;;
esac

if ! curl -fsSL --max-time 20 "$REPO_URL/$shas/install.sh" -o "$tmpdir/pinned" ||
  ! curl -fsSL --max-time 20 "$REPO_URL/$main_sha/install.sh" -o "$tmpdir/main"; then
  echo "check-bootstrap-pin: could not fetch install.sh — skipping pin check"
  exit 0
fi

if cmp -s "$tmpdir/pinned" "$tmpdir/main"; then
  echo "check-bootstrap-pin: OK — pinned $shas serves the same install.sh as main"
  exit 0
fi

if [ "$fix" = yes ]; then
  # The pin exists so a human reviews the exact install.sh bytes. Print
  # what changed before adopting the new SHA, so --fix is never blind.
  echo "check-bootstrap-pin: install.sh diff $shas -> $main_sha" >&2
  diff -u "$tmpdir/pinned" "$tmpdir/main" | cat -v >&2 || true
  sed -i "s|$repo/$shas/install\.sh|$repo/$main_sha/install.sh|g" "$README_FILE"
  echo "check-bootstrap-pin: bumped $README_FILE from $shas to $main_sha"
  echo "check-bootstrap-pin: review the diff above before committing"
  exit 0
fi

cat >&2 <<EOF
check-bootstrap-pin: $README_FILE pins $shas, which no longer matches
$repo main. The documented one-liner is serving stale code.

Rewrite every pinned URL in $README_FILE to $main_sha:

  sh scripts/check-bootstrap-pin.sh --fix
EOF
exit 1
