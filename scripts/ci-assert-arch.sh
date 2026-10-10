#!/bin/bash
# Fail closed when the CI runner is not linux x86_64.
#
# Every tool install in the CI workflow requests a hardcoded linux
# x86_64/amd64 release asset (linux_x64, linux_amd64, Linux_x86_64,
# Linux-64bit, linux-amd64, linux-x86_64). Those downloads succeed and
# their vendor checksums verify on any architecture -- the binaries just
# fail to execute later with "Exec format error", which is a confusing
# way to learn that a runner changed. GitHub, GitLab and Gitea all offer
# arm64 runners now, and this workflow is copied verbatim into every
# project generated from this template, so the assumption has to be
# stated and checked rather than implied by an asset name.
#
# See the supply-chain policy comment at the top of
# .github/workflows/ci.yml for why those asset names are pinned at all.
#
# ARCH overrides the detected architecture so the failure path is
# testable: `ARCH=aarch64 bash scripts/ci-assert-arch.sh` must exit 1.
set -euo pipefail

arch="${ARCH:-$(uname -m)}"

case "$arch" in
  x86_64 | amd64)
    exit 0
    ;;
esac

cat >&2 <<EOF
ci-assert-arch: unsupported runner architecture: $arch

This workflow's tool installs are pinned to linux x86_64 release assets.
On $arch those assets download and checksum-verify but cannot execute.

Fix it one of two ways:
  - run this job on an x86_64 runner, or
  - add per-architecture asset names to the install steps and widen the
    accepted list in this script.
EOF
exit 1
