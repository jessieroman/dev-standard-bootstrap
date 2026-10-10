#!/bin/bash
# Write the issue tracker out as plain text, so git carries a copy no tool owns.
#
# bd keeps issues and `bd remember` memories in an embedded Dolt database
# (.beads/embeddeddolt/, gitignored) and syncs it through the non-standard
# `refs/dolt/data` ref. Both are binary and readable only by bd + Dolt, so
# nothing in a clone survives bd going away. `bd export` is deterministic, and
# `bd import` reads the result back, which makes this file the restore path.
#
# Run by the beads-export pre-commit job; safe to run by hand.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Fresh machines and CI have no bd and must still be able to commit.
command -v bd >/dev/null || exit 0
# A clone carries the export but no database until `bd init`.
bd where >/dev/null 2>&1 || exit 0

mkdir -p .beads
new=$(mktemp)
trap 'rm -f "$new"' EXIT
bd export --include-memories -o "$new"
if [ ! -s "$new" ] && [ -s .beads/issues.jsonl ]; then
	echo "export-beads: the beads database is empty but .beads/issues.jsonl is not. Run 'bd import' to restore it. Export skipped." >&2
	exit 0
fi
# cat keeps the file mode.
cat "$new" >.beads/issues.jsonl

# A consumer whose .gitignore still ignores .beads wholesale must not get a
# blocked commit from a job it cannot see the cause of.
git add .beads/issues.jsonl 2>/dev/null || echo "export-beads: .beads/issues.jsonl is git-ignored, not staged"

# The standards-checks job scanned the index before this job staged the export,
# so scan again only when the export changed. A leak exits non-zero and blocks
# the commit (set -e). -v prints the rule and file.
if command -v gitleaks >/dev/null 2>&1 &&
	! git diff --cached --quiet -- .beads/issues.jsonl; then
	gitleaks git --staged --no-banner --redact -v .
fi
