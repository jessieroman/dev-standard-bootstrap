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
# install.sh checks out the newest v* release tag, so this file never needs
# a bump when dev-standard releases. Override with DEV_STANDARDS_REF=<tag or
# commit> to install a different revision.
#
# Needs this machine's SSH key already added to GitHub with read access to
# the private dev-standard repo. No GitHub token/PAT needed.
set -eu

repo_url="${DEV_STANDARDS_REPO_URL:-git@github.com:jessieroman/dev-standard.git}"
dest="${DEV_STANDARDS_DIR:-$HOME/git/dev-standards}"
ref="${DEV_STANDARDS_REF:-}"

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

git -C "$dest" fetch --quiet --tags origin
# ponytail: trusts whoever can push a v* tag to dev-standard; sign tags and
# run git verify-tag here if anyone besides the owner gets write access.
[ -n "$ref" ] || ref=$(git -C "$dest" tag -l 'v*' --sort=-v:refname | sed -n 1p)
[ -n "$ref" ] || die "install.sh: no v* release tag found in $dest"
log "checking out $ref"
git -C "$dest" checkout --quiet --detach "$ref^{commit}" ||
  die "install.sh: cannot check out $ref"

log "handing off to $dest/setup.sh"
# No cd: setup.sh targets the caller's directory by default.
exec "$dest/setup.sh" "$@"
