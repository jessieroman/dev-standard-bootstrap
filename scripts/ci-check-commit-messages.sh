#!/bin/bash
# CI mirror of the commit-msg hook's header, Refs-trailer and New-Doc
# checks, run against every commit in the PR/push range. Local hooks are
# bypassable with --no-verify; this is the actual enforcement layer. The
# paired-test heuristic isn't re-checked per-commit here (that's the hook's
# job at commit time plus human review) — this re-checks the cheap,
# unambiguous rules: format, traceability and a reason for new markdown.
# It also scans the range's history for secrets.
set -euo pipefail

RANGE="${1:?usage: ci-check-commit-messages.sh <base>..<head>}"
CC_RE='^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)(\([a-z0-9._/-]+\))?!?: .+'
REF_RE='^(Refs|Fixes|Closes):[[:space:]]*(#[0-9]+|[a-zA-Z][a-zA-Z0-9-]*-[0-9a-zA-Z]+(\.[0-9]+)?|https?://[^[:space:]]+)$'

# Assign first: under set -e a failing `git rev-list` aborts here, whereas
# a `< <(...)` process substitution would hide the failure and exit 0.
# Merge commits are exempt, matching scripts/commit-msg-checks.sh line 13.
commits="$(git rev-list --no-merges "$RANGE")"
fail=0
for sha in $commits; do
  msg="$(git log -1 --format=%B "$sha")"
  header="$(echo "$msg" | head -n1)"
  if ! [[ "$header" =~ $CC_RE ]]; then
    echo "commit $sha: header must follow Conventional Commits — got: $header" >&2
    fail=1
  fi
  if ! echo "$msg" | grep -qiE "$REF_RE"; then
    echo "commit $sha: missing an issue/bead reference trailer (Refs:/Fixes:/Closes:)" >&2
    fail=1
  fi
  # Mirrors scripts/commit-msg-checks.sh step 4. -M keeps a pure rename
  # from listing its destination as an added file. -z stops git C-quoting
  # non-ASCII names, which hid the .md suffix from the filter.
  if ! echo "$msg" | grep -qiE '^New-Doc:\s*\S+'; then
    docs="$(git diff-tree -z -M --no-commit-id --name-only -r --root --diff-filter=A "$sha" \
      | grep -zE '\.(md|markdown)$' | grep -zvE '^\.beads/|CHANGELOG\.md$' | tr '\0' ' ' || true)"
    if [ -n "$docs" ]; then
      echo "commit $sha: new markdown file(s) need a New-Doc: <reason> trailer: $docs" >&2
      fail=1
    fi
  fi
done

# The tree scan in CI sees only HEAD. A secret committed and then deleted
# inside the range is still in its history. --diff-merges=remerge also
# scans what a merge commit itself added, without blaming the PR for base
# changes it merged in; gitleaks skips merge diffs otherwise. Soft on a
# missing gitleaks, so a consumer CI that installs no tools in this job
# keeps passing.
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks git --no-banner --redact -v \
    --log-opts="--diff-merges=remerge $RANGE" . || fail=1
else
  echo "ci-check-commit-messages: gitleaks not on PATH; history not scanned for secrets" >&2
fi

exit "$fail"
