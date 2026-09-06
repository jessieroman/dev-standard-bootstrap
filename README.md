# dev-standard-bootstrap

Public one-liner entrypoint for [jessieroman/dev-standard](https://github.com/jessieroman/dev-standard)
(private). GitHub has no per-file visibility — a private repo can't
serve one public raw file — so this tiny public repo exists purely to
give the private repo's `setup.sh` a stable, unauthenticated `curl | sh`
URL:

```bash
curl -fsSL https://raw.githubusercontent.com/jessieroman/dev-standard-bootstrap/main/install.sh | sh -s -- /path/to/target-project
```

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
