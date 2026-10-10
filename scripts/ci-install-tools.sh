#!/bin/bash
# Install the third-party tools scripts/pre-commit-checks.sh runs, into
# one bin directory whose path is printed as the LAST line of stdout.
#
# This script is deliberately CI-system agnostic: it reads no
# forge-injected scratch-directory or PATH-append variable, and gates
# each install on a plain file test instead of a workflow expression,
# so GitHub Actions, GitLab CI and Gitea/Forgejo Actions can all call
# this identical file. Each system puts the printed directory on PATH
# its own way:
#
#   Actions   append the printed line to the forge's PATH file
#   GitLab    PATH="$(bash scripts/ci-install-tools.sh):$PATH"
#   locally   BIN=~/.local/bin bash scripts/ci-install-tools.sh
#
# Everything except that final path goes to stderr, so the caller can
# capture stdout without parsing progress output.
#
# Which tools get installed is decided by the same file-presence tests
# scripts/pre-commit-checks.sh gates its checks on — `[ -f
# pyproject.toml ]` and friends — so a repo with no Terraform never
# downloads tflint. That gating lives here rather than in the calling
# workflow because a step conditional is forge-specific and a `[ -f ]`
# test is not.
#
# Supply-chain policy for these installs: every release-asset download
# is pinned to a tag AND to a SHA-256 digest recorded in this file, and
# is checked against that digest before it is executed. The expected
# bytes live in this repo, not next to the asset upstream, so an asset
# re-uploaded under the same tag fails the install. Two exceptions,
# documented at their install blocks: biome (npm registry digest) and the
# apt-installed shellcheck (signed index). Python tools install
# from hash-locked files in scripts/ci-requirements/, which pin every
# transitive dependency too; each gets its own venv because their
# dependency sets conflict. No `curl | bash`, no `releases/latest`, no
# sdist builds. This script is copied verbatim into every project
# generated from this template, so a mutable ref piped into a shell here
# hands all of those projects to whoever compromises an upstream repo.
#
# Renovate moves each tag and its digest in one PR (see renovate.json).
# Its github-release-attachments datasource looks releases up by exact
# tag, so pins keep the upstream `v`; asset names strip it with
# ${VAR#v}. Renovate's pip-compile manager re-locks
# scripts/ci-requirements/*.txt when a version in the *.in file moves.
#
# Every pin is a ${VAR:-value} default with a `# renovate:` annotation on
# the line above; scripts/check-pinned-urls.sh enforces that. Assets are
# linux x86_64 only, and scripts/ci-assert-arch.sh fails closed elsewhere,
# so changing `runs-on` means revisiting asset names. renovate.json holds
# no platform/token/endpoint: run Renovate per forge (npm CLI or the
# ghcr.io/renovatebot/renovate container on GitHub/Gitea/Forgejo cron,
# gitlab.com/renovate-bot/renovate-runner on GitLab).
set -euo pipefail

# renovate: datasource=github-release-attachments depName=gitleaks/gitleaks
GITLEAKS_VERSION="${GITLEAKS_VERSION:-v8.30.1}"
GITLEAKS_SHA256="${GITLEAKS_SHA256:-551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb}"
# gastownhall/beads is the canonical repo. steveyegge/beads is the
# pre-rename namespace and only resolves via GitHub's rename redirect; a
# freed owner/name pair can be re-registered by anyone, which is exactly
# how a redirect turns into an attacker's payload.
# renovate: datasource=github-release-attachments depName=gastownhall/beads
BEADS_VERSION="${BEADS_VERSION:-v1.3.1}"
BEADS_SHA256="${BEADS_SHA256:-3219443a9734b89b93fb16ee8d65844759fa1b3cd3cf139c606b7353cfb0715c}"
# renovate: datasource=github-release-attachments depName=evilmartians/lefthook
LEFTHOOK_VERSION="${LEFTHOOK_VERSION:-v2.1.15}"
LEFTHOOK_SHA256="${LEFTHOOK_SHA256:-df981b477c236546435047fb8c8ee1f6f902e17faebb1b07b6bf2165832e8fe3}"
# renovate: datasource=github-release-attachments depName=terraform-linters/tflint
TFLINT_VERSION="${TFLINT_VERSION:-v0.64.0}"
TFLINT_SHA256="${TFLINT_SHA256:-cca9d13e2e1d7a2c627af60ff899a3c9b74212899416aeb96ec764d2ef954537}"
# renovate: datasource=github-release-attachments depName=aquasecurity/trivy
TRIVY_VERSION="${TRIVY_VERSION:-v0.74.0}"
TRIVY_SHA256="${TRIVY_SHA256:-2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a}"
# renovate: datasource=github-release-attachments depName=yannh/kubeconform
KUBECONFORM_VERSION="${KUBECONFORM_VERSION:-v0.8.0}"
KUBECONFORM_SHA256="${KUBECONFORM_SHA256:-9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883}"
# stackrox/kube-linter publishes no checksum file, so Renovate finds the
# pinned asset by hashing release assets until one matches.
# renovate: datasource=github-release-attachments depName=stackrox/kube-linter
KUBE_LINTER_VERSION="${KUBE_LINTER_VERSION:-v0.8.3}"
KUBE_LINTER_SHA256="${KUBE_LINTER_SHA256:-618d299a3e2839c8ca9d86fce0db617be0fba41f0fecbbbfb7fbf1c04299fae1}"
# Helm serves its tarballs from get.helm.sh, not the GitHub release, so
# renovate.json's custom.helm datasource reads the digest from the
# Linux amd64 line of Helm's release notes.
# renovate: datasource=custom.helm depName=helm/helm
HELM_VERSION="${HELM_VERSION:-v4.3.0}"
HELM_SHA256="${HELM_SHA256:-86584a54def73570558f66f5111cc53dfed56689637ae32c1201205d494f54fb}"
# renovate: datasource=github-release-attachments depName=hadolint/hadolint
HADOLINT_VERSION="${HADOLINT_VERSION:-v2.15.1}"
HADOLINT_SHA256="${HADOLINT_SHA256:-c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507}"
# renovate: datasource=github-release-attachments depName=vale-cli/vale
VALE_VERSION="${VALE_VERSION:-v3.24.0}"
VALE_SHA256="${VALE_SHA256:-867534ddb678abca7f214bc4706ead0922bd5252ffe8035fc227013f66c8b214}"
# registry.npmjs.org -> @biomejs/cli-linux-x64 dist.integrity (SHA-512)
# Biome's GitHub releases publish no checksum file. The npm registry
# records a digest for every tarball, and a published npm version is
# immutable, so that registry digest is the vendor-side attestation.
# renovate: datasource=npm depName=@biomejs/cli-linux-x64
BIOME_VERSION="${BIOME_VERSION:-2.5.15}"

BIN="${BIN:-$HOME/.local/bin}"
mkdir -p "$BIN"
req_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/ci-requirements"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

log() { echo "ci-install-tools: $*" >&2; }

# fetch_verified URL SHA256 DEST
#
# Downloads URL, checks it against SHA256 from the pins above, and only
# then moves it to DEST. A digest mismatch or a failed download returns
# non-zero and leaves DEST alone, so nothing unverified is executed.
fetch_verified() {
  local url=$1 sha256=$2 dest=$3
  local work
  work=$(mktemp -d "$tmp/fetch.XXXXXX")
  curl -fsSL --retry 3 -o "$work/asset" "$url"
  echo "$sha256  $work/asset" | sha256sum -c --strict >&2
  mv -f "$work/asset" "$dest"
}

# Debian and Ubuntu ship the venv module in a separate python3-venv
# package. GitHub's ubuntu runners include it; many container images do not.
ensure_venv() {
  python3 -c 'import ensurepip, venv' 2>/dev/null && return
  if command -v apt-get >/dev/null 2>&1 &&
      { [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; }; then
    log "installing python3-venv via apt"
    as_root apt-get update >&2
    as_root apt-get install -y python3-venv >&2
  else
    log "python3 with the venv module is required: install python3-venv"
    return 1
  fi
}

# venv_install TOOL
#
# Installs TOOL and every dependency from the hash-locked
# scripts/ci-requirements/TOOL.txt into its own venv, then links the
# entry point into BIN. --require-hashes rejects any wheel whose digest
# is not in that file.
venv_install() {
  local tool=$1 venv="$BIN/.venvs/$1"
  log "installing $tool from scripts/ci-requirements/$tool.txt"
  ensure_venv
  python3 -m venv --clear "$venv" >&2
  "$venv/bin/pip" install --quiet --disable-pip-version-check \
    --only-binary=:all: --require-hashes -r "$req_dir/$tool.txt" >&2
  ln -sf "$venv/bin/$tool" "$BIN/$tool"
}

# Package installs need root on a VM runner and already have it in a
# container; nothing else in this script does.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

log "installing gitleaks $GITLEAKS_VERSION"
gl="https://github.com/gitleaks/gitleaks/releases/download/$GITLEAKS_VERSION"
fetch_verified "$gl/gitleaks_${GITLEAKS_VERSION#v}_linux_x64.tar.gz" \
  "$GITLEAKS_SHA256" "$tmp/gitleaks.tar.gz"
tar -xzf "$tmp/gitleaks.tar.gz" -C "$BIN" gitleaks

log "installing beads $BEADS_VERSION"
bd="https://github.com/gastownhall/beads/releases/download/$BEADS_VERSION"
fetch_verified "$bd/beads_${BEADS_VERSION#v}_linux_amd64.tar.gz" \
  "$BEADS_SHA256" "$tmp/beads.tar.gz"
tar -xzf "$tmp/beads.tar.gz" -C "$BIN" bd

# Real asset naming is lefthook_<v>_Linux_x86_64 (capitalised OS name,
# GNU arch). The lefthook_$(uname -s)_$(uname -m) asset this install
# used to request never existed, so the curl always failed and an
# unpinned `npm install -g lefthook` silently took over. Both are gone;
# this fails loudly.
log "installing lefthook $LEFTHOOK_VERSION"
lh="https://github.com/evilmartians/lefthook/releases/download/$LEFTHOOK_VERSION"
fetch_verified "$lh/lefthook_${LEFTHOOK_VERSION#v}_Linux_x86_64" \
  "$LEFTHOOK_SHA256" "$BIN/lefthook"
chmod +x "$BIN/lefthook"

# apt is the one install path with no explicit pin here: its integrity
# comes from the distribution's GPG-signed release index, which apt
# refuses to bypass. Skipped when the image already ships shellcheck,
# and skipped with a warning where apt or root is unavailable —
# pre-commit-checks.sh treats shellcheck as a soft dependency and passes
# over the shell pass instead of failing.
if ! command -v shellcheck >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1 &&
      { [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; }; then
    log "installing shellcheck via apt"
    as_root apt-get update >&2
    as_root apt-get install -y shellcheck >&2
  else
    log "no apt-get or no root: skipping shellcheck"
  fi
fi

# yamllint is wanted in every repo (this template ships YAML of its
# own); ruff only where there is Python.
venv_install yamllint
if [ -f pyproject.toml ]; then
  venv_install ruff
fi

if [ -f ansible.cfg ]; then
  venv_install ansible-lint
fi

if [ -f .tflint.hcl ]; then
  log "installing tflint $TFLINT_VERSION"
  tf="https://github.com/terraform-linters/tflint/releases/download/$TFLINT_VERSION"
  fetch_verified "$tf/tflint_linux_amd64.zip" "$TFLINT_SHA256" \
    "$tmp/tflint.zip"
  unzip -oq "$tmp/tflint.zip" -d "$BIN"
  chmod +x "$BIN/tflint"
fi

if [ -f .tflint.hcl ] || [ -f .kube-linter.yaml ]; then
  venv_install checkov
  log "installing trivy $TRIVY_VERSION"
  tv="https://github.com/aquasecurity/trivy/releases/download/$TRIVY_VERSION"
  fetch_verified "$tv/trivy_${TRIVY_VERSION#v}_Linux-64bit.tar.gz" \
    "$TRIVY_SHA256" "$tmp/trivy.tar.gz"
  tar -xzf "$tmp/trivy.tar.gz" -C "$BIN" trivy
fi

if [ -f .kube-linter.yaml ]; then
  log "installing kubeconform $KUBECONFORM_VERSION"
  kc="https://github.com/yannh/kubeconform/releases/download/$KUBECONFORM_VERSION"
  fetch_verified "$kc/kubeconform-linux-amd64.tar.gz" \
    "$KUBECONFORM_SHA256" "$tmp/kubeconform.tar.gz"
  tar -xzf "$tmp/kubeconform.tar.gz" -C "$BIN" kubeconform

  log "installing kube-linter $KUBE_LINTER_VERSION"
  kl="https://github.com/stackrox/kube-linter/releases/download/$KUBE_LINTER_VERSION"
  fetch_verified "$kl/kube-linter-linux" "$KUBE_LINTER_SHA256" \
    "$tmp/kube-linter"
  install -m 0755 "$tmp/kube-linter" "$BIN/kube-linter"

  log "installing helm $HELM_VERSION"
  fetch_verified "https://get.helm.sh/helm-$HELM_VERSION-linux-amd64.tar.gz" \
    "$HELM_SHA256" "$tmp/helm.tar.gz"
  tar -xzf "$tmp/helm.tar.gz" -C "$BIN" \
    --strip-components=1 linux-amd64/helm
fi

if [ -f .hadolint.yaml ]; then
  log "installing hadolint $HADOLINT_VERSION"
  hd="https://github.com/hadolint/hadolint/releases/download/$HADOLINT_VERSION"
  fetch_verified "$hd/hadolint-linux-x86_64" "$HADOLINT_SHA256" \
    "$BIN/hadolint"
  chmod +x "$BIN/hadolint"
fi

if [ -f .vale.ini ]; then
  log "installing vale $VALE_VERSION"
  vl="https://github.com/vale-cli/vale/releases/download/$VALE_VERSION"
  fetch_verified "$vl/vale_${VALE_VERSION#v}_Linux_64-bit.tar.gz" \
    "$VALE_SHA256" "$tmp/vale.tgz"
  tar -xzf "$tmp/vale.tgz" -C "$BIN" vale
fi

# No checksum file on Biome's GitHub releases (see BIOME_VERSION above),
# so the digest comes from the npm registry: its version document records
# dist.integrity, base64 SHA-512 of the tarball. Decoded to hex here so
# the check is the same `sha*sum -c` as every other install.
if [ -f biome.json ]; then
  log "installing biome $BIOME_VERSION"
  bm="https://registry.npmjs.org/@biomejs/cli-linux-x64"
  curl -fsSL --retry 3 -o "$tmp/biome.json" "$bm/$BIOME_VERSION"
  curl -fsSL --retry 3 -o "$tmp/biome.tgz" \
    "$bm/-/cli-linux-x64-$BIOME_VERSION.tgz"
  sri=$(grep -o '"integrity":"sha512-[^"]*"' "$tmp/biome.json" | cut -d'"' -f4)
  printf '%s  biome.tgz\n' \
    "$(printf '%s' "${sri#sha512-}" | base64 -d | od -An -v -tx1 | tr -d ' \n')" \
    > "$tmp/biome.sha512"
  (cd "$tmp" && sha512sum -c --strict biome.sha512) >&2
  tar -xzf "$tmp/biome.tgz" -C "$tmp" package/biome
  install -m 0755 "$tmp/package/biome" "$BIN/biome"
fi

# Last line of stdout, and the only one: the caller puts this on PATH.
echo "$BIN"
