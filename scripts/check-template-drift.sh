#!/bin/sh
# Fail closed when a consumer's payload files no longer match what this
# template would generate at the consumer's own pinned version.
#
# CONTEXT: a consumer can edit a payload file (lefthook.yml, cliff.toml,
# pyproject.toml, ...) in place without ever touching .copier-answers.yml.
# `copier update` then conflicts instead of merging cleanly, and nothing
# reports the day the drift happens — the edit sits unnoticed until the
# next update. This guard reports it at commit time.
#
# This script ships as template payload, so it also runs inside this
# template repo's own checkout, which is not a consumer and carries no
# .copier-answers.yml. That is not a violation: zero answers file means
# there is nothing to compare against, so the script skips (exit 0).
#
# yq is not installed, so the pinned ref and source path are read with
# grep/cut instead of a YAML parser — .copier-answers.yml's format is
# fixed (one `key: value` per line, no nesting) so this is exact, not a
# heuristic.
set -eu

ANSWERS_FILE="${ANSWERS_FILE:-.copier-answers.yml}"
IGNORE_FILE="${IGNORE_FILE:-.template-drift-ignore}"

if [ ! -f "$ANSWERS_FILE" ]; then
  echo "check-template-drift: no $ANSWERS_FILE — not a template consumer, skipping"
  exit 0
fi

if ! command -v copier >/dev/null 2>&1; then
  echo "check-template-drift: copier not installed — skipping drift check"
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "check-template-drift: git not installed — skipping drift check"
  exit 0
fi

ref=$(grep '^_commit:' "$ANSWERS_FILE" | cut -d' ' -f2)
src=$(grep '^_src_path:' "$ANSWERS_FILE" | cut -d' ' -f2)

if [ -z "$ref" ] || [ -z "$src" ]; then
  echo "check-template-drift: $ANSWERS_FILE has no _commit/_src_path — skipping drift check"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gen="$tmp/gen"
own="$tmp/own"
mkdir "$gen" "$own"

# regenerate <dest> [--overwrite]: render the template at $ref into <dest>.
# No --trust: this template declares no _tasks/_migrations, and trusting
# a repo-controlled _src_path would let an edited .copier-answers.yml run
# arbitrary template hooks on the committer's machine (CWE-94).
regenerate() {
  copier copy --defaults ${2:+"$2"} --vcs-ref "$ref" --data-file "$ANSWERS_FILE" "$src" "$1" >/dev/null 2>&1
}

if ! regenerate "$gen"; then
  echo "check-template-drift: could not regenerate template at $ref — skipping drift check"
  exit 0
fi

# Second pass: pre-seed the project's own copy of every payload file, then
# regenerate with --overwrite. Copier leaves files listed in the template's
# `_skip_if_exists` untouched (the project owns them) and overwrites the
# rest, so comparing against $own never flags a project-owned file and needs
# no copy of that list here.
find "$gen" -mindepth 1 -type f | while IFS= read -r generated; do
  rel=${generated#"$gen"/}
  if [ -f "$rel" ]; then
    mkdir -p "$own/$(dirname "$rel")"
    cp "$rel" "$own/$rel"
  fi
done

if ! regenerate "$own" --overwrite; then
  echo "check-template-drift: could not regenerate template at $ref — skipping drift check"
  exit 0
fi

drift=0
find "$gen" -mindepth 1 -type f | while IFS= read -r generated; do
  rel=${generated#"$gen"/}

  if [ -f "$IGNORE_FILE" ] && grep -Fxq "$rel" "$IGNORE_FILE"; then
    continue
  fi

  if [ ! -f "$rel" ]; then
    continue
  fi

  if ! cmp -s "$own/$rel" "$rel"; then
    echo "DRIFT $rel"
    echo drift >"$tmp/.drift-flag"
  fi
done

if [ -f "$tmp/.drift-flag" ]; then
  drift=1
fi

if [ "$drift" -ne 0 ]; then
  echo "check-template-drift: payload files differ from the template at $ref" >&2
  exit 1
fi

echo "check-template-drift: OK — payload matches template at $ref"
exit 0
