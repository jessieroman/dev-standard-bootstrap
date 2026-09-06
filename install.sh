#!/bin/sh
# Public one-liner entrypoint for jessieroman/dev-standard (that repo is
# private, so its own setup.sh can't be curl|sh'd directly -- see
# jessieroman/dev-standard/README.md's "Already have SSH access" note).
#
#   curl -fsSL https://raw.githubusercontent.com/jessieroman/dev-standard-bootstrap/main/install.sh | sh -s -- /path/to/target-project
#
# Kept deliberately tiny and stable: clone/update the private repo over
# SSH, then hand off entirely to its own setup.sh (target project path +
# any flags passed after `--`). Every actual install decision (which
# use_* toggles, the TUI, copier) lives there and can change freely
# without ever touching this URL or this file.
#
# Needs this machine's SSH key already added to GitHub (git clone auth).
# No GitHub token/PAT needed -- this repo is public.
set -eu

repo_url="${DEV_STANDARDS_REPO_URL:-git@github.com:jessieroman/dev-standard.git}"
dest="${DEV_STANDARDS_DIR:-$HOME/git/dev-standards}"

log() { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
die() { printf '\033[1;33m!!\033[0m %s\n' "$1" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "install.sh: git is required (clone/update the dev-standard repo)"

if [ -d "$dest/.git" ]; then
  log "updating existing clone at $dest"
  git -C "$dest" pull --ff-only
else
  log "cloning $repo_url to $dest"
  mkdir -p "$(dirname "$dest")"
  git clone "$repo_url" "$dest"
fi

log "handing off to $dest/setup.sh"
cd "$dest"
exec ./setup.sh "$@"
