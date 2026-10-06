# dev-standard-bootstrap

Public one-liner entrypoint for [jessieroman/dev-standard](https://github.com/jessieroman/dev-standard)
(private). GitHub has no per-file visibility — a private repo can't
serve one public raw file — so this tiny public repo exists purely to
give the private repo's `setup.sh` a stable, unauthenticated `curl | sh`
URL:

```bash
curl -fsSL https://raw.githubusercontent.com/jessieroman/dev-standard-bootstrap/main/install.sh | sh
```

`main` is protected (`enforce_admins`, no force-push, no deletion,
linear history). A push to `main` is live for the one-liner at once.

The clone follows releases: `install.sh` checks out the newest `v*` tag
of `jessieroman/dev-standard`, so a `dev-standard` release needs no
change here. Override that revision with `DEV_STANDARDS_REF`.

Anything after `-s --` is forwarded to `setup.sh` unchanged — e.g. add
`--yes` to skip the checkbox TUI, or `--prefix myproj`.

`install.sh` here does exactly one thing: clone or update
`jessieroman/dev-standard` over SSH into `~/.cache/dev-standard`
(`$XDG_CACHE_HOME` respected; override with
`DEV_STANDARDS_DIR`/`DEV_STANDARDS_REPO_URL`), then exec that
repo's own `setup.sh`. Every actual install decision — which `use_*`
toggles, the Textual checkbox TUI, the copier template itself — lives
in the private repo and can change freely without ever touching this
file or its URL.

Requires this machine's SSH key already added to GitHub, with read
access to the private `dev-standard` repo. No GitHub token/PAT needed.

Nothing sensitive lives here on purpose: no secrets, no other
machine-specific config. Just the pull-and-handoff step.
