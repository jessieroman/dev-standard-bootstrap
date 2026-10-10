#!/bin/bash
# Commit-msg checks, run via lefthook.yml. Four checks: Conventional
# Commits header, TDD-where-plausible paired-test check, a required
# issue/bead reference trailer (no exceptions), and a New-Doc reason for
# added markdown files. See docs/conventional-commits.md.
set -euo pipefail

MSG_FILE="$1"
HEADER="$(head -n1 "$MSG_FILE")"
fail=0

# git-generated headers (local merge, fixup, squash, revert) are exempt.
if [[ "$HEADER" =~ ^(Merge\ |Revert\ \"|fixup!\ |squash!\ |amend!\ ) ]]; then
  exit 0
fi

# --- 1. Conventional Commits header --------------------------------------
CC_RE='^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)(\([a-z0-9._/-]+\))?!?: .+'
if ! [[ "$HEADER" =~ $CC_RE ]]; then
  echo "commit-msg: header must follow Conventional Commits — '<type>(<scope>)?: <description>'" >&2
  echo "commit-msg: types: feat fix chore docs style refactor perf test build ci revert" >&2
  echo "commit-msg: got: $HEADER" >&2
  fail=1
fi

# --- 2. TDD-where-plausible paired-test check -----------------------------
if grep -qiE '^No-Test-Needed:\s*\S+' "$MSG_FILE"; then
  : # explicit, reasoned override present — trust it
else
  # -M100% reports only exact renames as R, so a pure move needs no test but an edited rename does.
  staged="$(git diff --cached --name-only -M100% --diff-filter=ACM || true)"
  if [ -n "$staged" ]; then
    src="$(echo "$staged" | grep -vE '\.(md|markdown|txt|jsonl?|ya?ml|toml|ini|cfg|lock|example|gitignore|gitattributes)$|(^|/)(LICENSE|CHANGELOG)|^\.beads/' || true)"
    if [ -n "$src" ]; then
      has_test="$(echo "$staged" | grep -iE '(^|/)(tests?|specs?|__tests__)(/|$)|[_.](test|spec)\.[a-zA-Z0-9]+$|(^|/)test_[^/]+$' || true)"
      if [ -z "$has_test" ]; then
        echo "commit-msg: source files changed with no paired test change:" >&2
        echo "$src" | sed 's/^/  /' >&2
        echo "commit-msg: add a test, or add a trailer: No-Test-Needed: <reason>" >&2
        fail=1
      fi
    fi
  fi
fi

# --- 3. Issue/bead reference required, no exceptions ----------------------
REF_RE='^(Refs|Fixes|Closes):[[:space:]]*(#[0-9]+|[a-zA-Z][a-zA-Z0-9-]*-[0-9a-zA-Z]+(\.[0-9]+)?|https?://[^[:space:]]+)$'
if ! grep -qiE "$REF_RE" "$MSG_FILE"; then
  echo "commit-msg: missing an issue/bead reference trailer, e.g.:" >&2
  echo "  Refs: proj-36x       (beads ID)" >&2
  echo "  Refs: #123           (GitHub/GitLab issue)" >&2
  echo "  Refs: https://github.com/org/repo/issues/123" >&2
  fail=1
fi

# --- 4. New markdown file needs a reason ---------------------------------
if grep -qiE '^New-Doc:\s*\S+' "$MSG_FILE"; then
  : # explicit, reasoned override present — trust it
else
  # -z stops git C-quoting non-ASCII names, which hid the .md suffix.
  docs="$(git diff --cached -z --name-only --diff-filter=A |
    grep -zE '\.(md|markdown)$' | grep -zvE '^\.beads/|CHANGELOG\.md$' | tr '\0' '\n' || true)"
  if [ -n "$docs" ]; then
    echo "commit-msg: new markdown file(s) need a New-Doc: <reason> trailer:" >&2
    sed 's/^/  /' <<<"$docs" >&2
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "commit-msg: fix the above or 'git commit --no-verify' to bypass" >&2
  exit 1
fi
