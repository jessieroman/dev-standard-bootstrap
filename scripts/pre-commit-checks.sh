#!/bin/bash
# Lint/scan checks, run via lefthook.yml (checked into this repo — never
# a personal global hooksPath) and mirrored in CI. gitleaks and beads are
# hard requirements; language/IaC linters are soft (skip silently if the
# binary isn't installed — not every repo using this template needs every
# language).
#
# Usage: pre-commit-checks.sh [staged|all]
#
#   staged  (default) Check only the files staged for the current commit,
#           and scan the staged diff for secrets. This is the pre-commit
#           hook path: fast, and scoped to what is actually being added.
#   all     Check every tracked file, and scan the whole working tree for
#           secrets. This is the CI path. Local hooks are bypassable with
#           `git commit --no-verify`, so CI must not inherit the hook's
#           staged-only scope: in CI nothing is ever staged, which would
#           silently reduce every check to a no-op.
set -euo pipefail

MODE="${1:-staged}"
case "$MODE" in
  staged | all) ;;
  *)
    echo "pre-commit: unknown mode '$MODE' — expected 'staged' or 'all'" >&2
    echo "usage: $0 [staged|all]" >&2
    exit 2
    ;;
esac

fail=0

# Single source of truth for which files every check below looks at.
#
# NUL-delimited on purpose. git's newline-delimited output *quotes* any
# path containing a space or a newline, and an unquoted expansion of that
# list word-splits and glob-expands the rest — so a crafted filename
# could vanish from every scan, or arrive at a linter as an option. A
# leading dash is rewritten to `./-…` once, here, because not every
# linter downstream honours a `--` end-of-options marker.
all_files=()
while IFS= read -r -d '' f; do
  case "$f" in -*) f="./$f" ;; esac
  all_files+=("$f")
done < <(
  case "$MODE" in
    staged) git diff --cached -z --name-only --diff-filter=ACMR ;;
    all) git ls-files -z ;;
  esac
)

# select_files <glob>… — fills `selected` with the matching subset of
# `all_files`, in order, each file at most once. Callers must use
# `selected` (or copy it) before the next call.
selected=()
select_files() {
  selected=()
  if [ "${#all_files[@]}" -eq 0 ]; then
    return 0
  fi
  local file pattern
  for file in "${all_files[@]}"; do
    for pattern in "$@"; do
      # The pattern is meant to glob; quoting it (SC2254) would match it
      # literally and select nothing.
      # shellcheck disable=SC2254
      case "$file" in
        $pattern)
          selected+=("$file")
          break
          ;;
      esac
    done
  done
}

# Helm charts: find the nearest Chart.yaml above each candidate path, once
# per chart. Computed first so other checks (yamllint, raw k8s manifest
# detection) can exclude chart template files -- they contain unrendered
# Go template syntax mixed with literal YAML (e.g. `{{ .Values.x }}`
# next to `apiVersion:`), which is not valid standalone YAML and is not
# a real manifest until rendered. kube-linter and `helm lint` render
# templates themselves, so they check charts correctly; kubeconform and
# yamllint would otherwise misfire on the same files.
chart_dirs=()
if [ "${#all_files[@]}" -gt 0 ] &&
  { command -v helm >/dev/null 2>&1 || command -v kube-linter >/dev/null 2>&1; }; then
  for f in "${all_files[@]}"; do
    dir="$(dirname "$f")"
    while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
      if [ -f "$dir/Chart.yaml" ]; then
        known=0
        if [ "${#chart_dirs[@]}" -gt 0 ]; then
          for d in "${chart_dirs[@]}"; do
            if [ "$d" = "$dir" ]; then
              known=1
              break
            fi
          done
        fi
        if [ "$known" -eq 0 ]; then
          chart_dirs+=("$dir")
        fi
        break
      fi
      dir="$(dirname "$dir")"
    done
  done
fi

in_chart_dir() {
  if [ "${#chart_dirs[@]}" -eq 0 ]; then
    return 1
  fi
  local d
  for d in "${chart_dirs[@]}"; do
    case "$1" in "$d"/*) return 0 ;; esac
  done
  return 1
}

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "pre-commit: gitleaks not found on PATH — secret scanning is required, or 'git commit --no-verify' to bypass" >&2
  exit 1
fi
# `git --staged` scans the staged patch; `dir` (aliases: file, directory)
# scans a directory tree on disk, which is the only mode that sees
# anything in CI where the index is empty.
case "$MODE" in
  staged) gitleaks git --staged --no-banner -v || fail=1 ;;
  all) gitleaks dir . --no-banner -v || fail=1 ;;
esac

if ! command -v bd >/dev/null 2>&1; then
  echo "pre-commit: bd (beads) not found on PATH — beads is required for this project, or 'git commit --no-verify' to bypass" >&2
  exit 1
fi

# Pins must stay annotated for renovate.json, and pinned URLs must resolve.
# Runs only when the installer or its locks change; in all mode they are
# tracked, so CI runs it.
if [ -f "$(dirname "$0")/check-pinned-urls.sh" ]; then
  select_files 'scripts/ci-install-tools.sh' 'scripts/ci-requirements/*'
  if [ "${#selected[@]}" -gt 0 ]; then
    bash "$(dirname "$0")/check-pinned-urls.sh" || fail=1
  fi
fi

if command -v shellcheck >/dev/null 2>&1; then
  select_files '*.sh' '*.bash'
  if [ "${#selected[@]}" -gt 0 ]; then
    shellcheck --severity=warning "${selected[@]}" || fail=1
  fi
fi

if command -v ruff >/dev/null 2>&1; then
  select_files '*.py'
  if [ "${#selected[@]}" -gt 0 ]; then
    ruff check "${selected[@]}" || fail=1
  fi
fi

# Biome lints TypeScript and JavaScript with one static binary, no
# node_modules. `--no-errors-on-unmatched` keeps a commit whose files are
# all excluded by biome.json `files.includes` from failing.
if command -v biome >/dev/null 2>&1; then
  select_files '*.ts' '*.tsx' '*.mts' '*.cts' '*.js' '*.jsx' '*.mjs' '*.cjs'
  if [ "${#selected[@]}" -gt 0 ]; then
    biome lint --no-errors-on-unmatched "${selected[@]}" || fail=1
  fi
fi

if command -v yamllint >/dev/null 2>&1; then
  select_files '*.yml' '*.yaml'
  yaml_files=()
  if [ "${#selected[@]}" -gt 0 ]; then
    for f in "${selected[@]}"; do
      in_chart_dir "$f" || yaml_files+=("$f")
    done
  fi
  if [ "${#yaml_files[@]}" -gt 0 ]; then
    yamllint "${yaml_files[@]}" || fail=1
  fi
fi

if command -v ansible-lint >/dev/null 2>&1 && [ -f ansible.cfg ]; then
  select_files '*.yml' '*.yaml'
  if [ "${#selected[@]}" -gt 0 ]; then
    ansible-lint "${selected[@]}" || fail=1
  fi
fi

if command -v tflint >/dev/null 2>&1; then
  select_files '*.tf'
  if [ "${#selected[@]}" -gt 0 ]; then
    tflint --recursive || fail=1
  fi
fi

if command -v checkov >/dev/null 2>&1; then
  select_files '*.tf' '*.yaml' '*.yml'
  if [ "${#selected[@]}" -gt 0 ]; then
    checkov --quiet --compact --file "${selected[@]}" || fail=1
  fi
fi

if command -v trivy >/dev/null 2>&1; then
  select_files '*.tf' '*.yaml' '*.yml'
  if [ "${#selected[@]}" -gt 0 ]; then
    trivy fs --scanners misconfig --quiet . || fail=1
  fi
fi

# Gate on manifest CONTENT (apiVersion + kind), not file location — a
# repo's own CI workflow YAML has neither, so it's never mistaken for a
# Kubernetes manifest. Chart template files are excluded (see chart_dirs
# above) and checked via the Helm-aware pass below instead.
k8s_files=()
if command -v kubeconform >/dev/null 2>&1 || command -v kube-linter >/dev/null 2>&1; then
  select_files '*.yml' '*.yaml'
  if [ "${#selected[@]}" -gt 0 ]; then
    for f in "${selected[@]}"; do
      if in_chart_dir "$f"; then
        continue
      fi
      if [ -f "$f" ] && grep -q '^apiVersion:' "$f" 2>/dev/null && grep -q '^kind:' "$f" 2>/dev/null; then
        k8s_files+=("$f")
      fi
    done
  fi
fi

# Custom resources (ExternalSecret, Application, ServiceMonitor, ...) have
# no schema in the default registry. Datree's CRDs-catalog covers the
# common ones. It is pinned to a reviewed commit, because a fetched schema
# decides pass/fail and kubeconform follows remote $refs inside it.
# Schemas are cached, so most runs make no request at all.
# A kind in neither registry FAILS: list in-house CRDs, one kind or
# group/version/kind per line, in .kubeconform-skip at the repo root.
# Flags from https://github.com/yannh/kubeconform#customresourcedefinition-crd-support
if command -v kubeconform >/dev/null 2>&1 && [ "${#k8s_files[@]}" -gt 0 ]; then
  kc_cache="${XDG_CACHE_HOME:-$HOME/.cache}/kubeconform"
  mkdir -p "$kc_cache"
  # The {{ }} fields are kubeconform's own template syntax, not shell.
  # shellcheck disable=SC2016
  kc_args=(-strict -summary -cache "$kc_cache"
    -schema-location default
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/d373c2da9702bc9509a004db83e57263fe3bdfc1/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json')
  kc_skip_file="$(git rev-parse --show-toplevel)/.kubeconform-skip"
  if [ -f "$kc_skip_file" ]; then
    kc_skip=$(grep -vE '^[[:space:]]*(#|$)' "$kc_skip_file" | paste -sd, -)
    [ -z "$kc_skip" ] || kc_args+=(-skip "$kc_skip")
  fi
  kubeconform "${kc_args[@]}" "${k8s_files[@]}" || fail=1
fi

if command -v kube-linter >/dev/null 2>&1 && [ "${#k8s_files[@]}" -gt 0 ]; then
  kube-linter lint "${k8s_files[@]}" || fail=1
fi

if command -v hadolint >/dev/null 2>&1; then
  # Matched on the basename, so a directory called `Dockerfile.d` does
  # not drag its contents in.
  docker_files=()
  if [ "${#all_files[@]}" -gt 0 ]; then
    for f in "${all_files[@]}"; do
      case "${f##*/}" in
        Dockerfile | Dockerfile.* | Dockerfile-*) docker_files+=("$f") ;;
      esac
    done
  fi
  if [ "${#docker_files[@]}" -gt 0 ]; then
    hadolint "${docker_files[@]}" || fail=1
  fi
fi

if command -v helm >/dev/null 2>&1 && [ "${#chart_dirs[@]}" -gt 0 ]; then
  for d in "${chart_dirs[@]}"; do
    helm lint "$d" || fail=1
  done
fi

if command -v kube-linter >/dev/null 2>&1 && [ "${#chart_dirs[@]}" -gt 0 ]; then
  for d in "${chart_dirs[@]}"; do
    kube-linter lint "$d" || fail=1
  done
fi

# Markdown that quotes a repo path in backticks must still point at a file
# that exists: a rename otherwise leaves the docs silently wrong. A token
# only counts when its first segment is a tracked top-level entry, so home
# paths, URLs and shell fragments are ignored. `<path>.jinja2` counts as
# present because copier payload files carry that suffix.
if command -v python3 >/dev/null 2>&1; then
  select_files '*.md' '*.md.jinja2'
  md_files=()
  if [ "${#selected[@]}" -gt 0 ]; then
    for f in "${selected[@]}"; do
      [ "${f##*/}" = CHANGELOG.md ] || md_files+=("$f")
    done
  fi
  if [ "${#md_files[@]}" -gt 0 ]; then
    printf '%s\0' "${md_files[@]}" |
      (cd "$(git rev-parse --show-toplevel)" && python3 - 3<&0 <<'PY') || fail=1
import os
import re
import subprocess
import sys

FENCE = re.compile(r"^```[^\n]*\n(.*?)^```", re.MULTILINE | re.DOTALL)
INLINE = re.compile(r"`([^`\n]+)`")
TOKEN = re.compile(r"(?<![~/\w$.-])[A-Za-z0-9_.][A-Za-z0-9_./-]*")
# `apiVersion: apps/v1` names a Kubernetes API group, not a repo path, and
# collides with any project that has a top-level `apps/` directory.
API_VERSION = re.compile(r"^\s*-?\s*apiVersion:.*$", re.MULTILINE)


def present(path, is_file=False):
    check = os.path.isfile if is_file else os.path.exists
    return check(path) or check(path + ".jinja2")


tracked = subprocess.run(
    ["git", "ls-files", "-z"], capture_output=True, text=True, check=True
).stdout
top_level = set()
for entry in tracked.split("\0"):
    if entry:
        head = entry.split("/", 1)[0]
        top_level.add(head)
        top_level.add(head.removesuffix(".jinja2"))

with os.fdopen(3, encoding="utf-8") as names:
    docs = [n for n in names.read().split("\0") if n]

missing_any = False
for doc in docs:
    with open(doc, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    regions = FENCE.findall(text) + INLINE.findall(FENCE.sub("\n", text))
    found = set()
    for region in regions:
        for token in TOKEN.findall(API_VERSION.sub("", region)):
            candidate = token.rstrip("/.,:;")
            head, _, tail = candidate.partition("/")
            if head not in top_level:
                continue
            # A bare top-level name is a path only when it is a file, never
            # when it is a directory used as a word ("scripts", "docs").
            if not tail and not present(candidate, is_file=True):
                continue
            found.add(candidate)
    for path in sorted(found):
        if present(path):
            continue
        # A gitignored path (local secrets, inventory) is absent from every
        # clone on purpose; the docs still need to name it.
        if subprocess.run(["git", "check-ignore", "-q", path], check=False).returncode == 0:
            continue
        print(f"doc-paths: {doc}: {path}", file=sys.stderr)
        missing_any = True

sys.exit(1 if missing_any else 0)
PY
  fi
  # Word budgets, AI-artifact filenames, duplicate paragraphs; see check-docs.py.
  if [ "${#md_files[@]}" -gt 0 ] && [ -f "$(dirname "$0")/check-docs.py" ]; then
    python3 "$(dirname "$0")/check-docs.py" "${md_files[@]}" || fail=1
  fi
  # Sentence length and filler words; see .vale/styles/Terse.
  if command -v vale >/dev/null 2>&1 && [ -f .vale.ini ] &&
    [ "${#md_files[@]}" -gt 0 ]; then
    vale_files=()
    for f in "${md_files[@]}"; do
      if [ -f .doc-sprawl-skip ] &&
        grep -vE '^[[:space:]]*(#|$)' .doc-sprawl-skip | grep -qxF "$f"; then
        continue
      fi
      vale_files+=("$f")
    done
    if [ "${#vale_files[@]}" -gt 0 ]; then
      vale --output=line "${vale_files[@]}" || fail=1
    fi
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "pre-commit: lint/scan checks found issues — fix or 'git commit --no-verify' to bypass" >&2
  exit 1
fi
