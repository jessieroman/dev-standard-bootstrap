# dev-standard-bootstrap

Public one-liner entrypoint for [jessieroman/dev-standard](https://github.com/jessieroman/dev-standard)
(private). GitHub has no per-file visibility — a private repo can't
serve one public raw file — so this tiny public repo exists purely to
give the private repo's `setup.sh` a stable, unauthenticated `curl | sh`
URL:

```bash
curl -fsSL https://raw.githubusercontent.com/jessieroman/dev-standard-bootstrap/596dd2e511b979e83e1288de0c3b280db35ba5e5/install.sh | sh
```

That URL is pinned to a commit SHA, not `main`. `main` is protected
(`enforce_admins`, no force-push, no deletion, linear history) but a
SHA pin adds a second, independent guarantee: even a legitimate push
to `main` can't silently change what an already-shared URL serves.
Bump the pin (in both this README and `jessieroman/dev-standard`'s own
README, which links here) whenever `install.sh` intentionally changes
— get the new SHA with
`gh api repos/jessieroman/dev-standard-bootstrap/commits/main --jq .sha`.

The clone is pinned the same way: `install.sh` checks out one exact
revision of `jessieroman/dev-standard` and refuses to exec `setup.sh`
when `git rev-parse HEAD` disagrees. Override that revision with
`DEV_STANDARDS_REF`. Bump the default in `install.sh` when
`dev-standard` releases.

Anything after `-s --` is forwarded to `setup.sh` unchanged — e.g. add
`--yes` to skip the checkbox TUI, or `--prefix myproj`.

`install.sh` here does exactly one thing: clone or update
`jessieroman/dev-standard` over SSH into `~/git/dev-standards` (override
with `DEV_STANDARDS_DIR`/`DEV_STANDARDS_REPO_URL`), then exec that
repo's own `setup.sh`. Every actual install decision — which `use_*`
toggles, the Textual checkbox TUI, the copier template itself — lives
in the private repo and can change freely without ever touching this
file or its URL.

Requires this machine's SSH key already added to GitHub (same
prerequisite `git clone git@github.com:...` always has). No GitHub
token/PAT needed — this repo is public.

Nothing sensitive lives here on purpose: no secrets, no other
machine-specific config. Just the pull-and-handoff step.
