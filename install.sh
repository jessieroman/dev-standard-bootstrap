#!/bin/sh
# Public one-liner entrypoint for jessieroman/dev-standard (that repo is
# private, so its own setup.sh can't be curl|sh'd directly -- see
# jessieroman/dev-standard/README.md's "Already have SSH access" note).
#
#   curl -fsSL https://raw.githubusercontent.com/jessieroman/dev-standard-bootstrap/main/install.sh | sh -s -- /path/to/target-project
#
# Kept deliberately tiny and stable: clone/update the private repo over
# SSH, check out one exact revision, then hand off entirely to its own
# setup.sh (target project path + any flags passed after `--`). Every
# actual install decision (which use_* toggles, the TUI, copier) lives
# there and can change freely without ever touching this URL or this file.
#
# The revision is pinned to a full commit SHA and verified after checkout,
# so this script always runs code someone reviewed, even if the repo's
# branches move. Override with DEV_STANDARDS_REF=<commit-ish> to install a
# different revision; the pin is still checked against what git landed on.
#
# Needs this machine's SSH key already added to GitHub (git clone auth).
# No GitHub token/PAT needed -- this repo is public.
set -eu

repo_url="${DEV_STANDARDS_REPO_URL:-git@github.com:jessieroman/dev-standard.git}"
dest="${DEV_STANDARDS_DIR:-$HOME/git/dev-standards}"
ref="${DEV_STANDARDS_REF:-0097041802286b4034e686373d3cdbb0949f6526}"

log() { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
die() { printf '\033[1;33m!!\033[0m %s\n' "$1" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "install.sh: git is required (clone/update the dev-standard repo)"

if [ -d "$dest/.git" ]; then
  log "updating existing clone at $dest"
  # A previous run leaves HEAD detached at the pin, where pull has no upstream.
  if git -C "$dest" symbolic-ref -q HEAD >/dev/null; then
    git -C "$dest" pull --ff-only
  fi
else
  log "cloning $repo_url to $dest"
  mkdir -p "$(dirname "$dest")"
  git clone "$repo_url" "$dest"
fi

log "checking out pinned revision $ref"
git -C "$dest" fetch --quiet origin "$ref" || true
git -C "$dest" checkout --quiet --detach "$ref" || true
got=$(git -C "$dest" rev-parse HEAD)
[ "$got" = "$ref" ] || die "install.sh: refusing to run unverified code -- wanted revision $ref but $dest is at $got"

log "handing off to $dest/setup.sh"
cd "$dest"
exec ./setup.sh "$@"
