# Conventional Commits (this project's convention)

Every commit message is checked by the checked-in `commit-msg` hook
(`lefthook.yml` → `scripts/commit-msg-checks.sh`), and mirrored in CI
(`.github/workflows/ci.yml`) since local hooks are bypassable with
`--no-verify`.

## Header (required)

```
<type>(<scope>)?: <description>
```

- `type` — one of: `feat fix chore docs style refactor perf test build ci revert`
- `scope` — optional, lowercase, e.g. `(auth)`, `(ci)`
- `!` after type/scope marks a breaking change: `feat(api)!: drop v1 endpoint`
- `description` — imperative mood, no trailing period

## Trailers (required)

Every commit needs an issue/bead reference trailer — no exceptions:

```
Refs: dev-standard-bootstrap-36x                             # beads ID
Refs: #123                                 # GitHub/GitLab issue, same repo
Refs: https://github.com/org/repo/issues/9 # cross-repo issue
```

Source changes need a paired test change in the same commit, unless
genuinely not applicable (docs, config/data with no logic, generated
files):

```
No-Test-Needed: infra bootstrap script, no unit-testable logic yet
```

A commit that adds a new `*.md`/`*.markdown` file (except `.beads/` and
`CHANGELOG.md`) needs a reason. Prefer extending an existing doc:

```
New-Doc: operator runbook, no existing doc covers deploys
```

## Full example

```
feat(auth): add refresh-token rotation

Rotates refresh tokens on every use to limit replay window.

Refs: dev-standard-bootstrap-42
```

## Why this exists

- The header format lets `cliff.toml` (git-cliff) generate changelogs
  and pick semver bumps automatically at release time.
- The `Refs:` trailer keeps every change traceable to a bead or issue.
- The paired-test trailer enforces TDD-where-plausible without silently
  skipping when a test genuinely isn't the right tool.

`git commit --no-verify` bypasses the local hook; CI still checks every
commit in a PR, so bypassing locally only defers the fix.
