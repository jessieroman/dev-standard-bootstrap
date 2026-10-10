#!/bin/bash
# Guard the two things a version pin needs to keep working: an
# annotation that lets automation bump it, and an upstream URL that
# still serves the pinned bytes.
# The pre-commit hook runs this when scripts/ci-install-tools.sh is
# staged; CI runs it on every change.
#
# ANNOTATION PASS (offline, FAILS the build). renovate.json bumps the
# pins in scripts/ci-install-tools.sh with a custom (regex) manager, and
# that manager can only see a pin it can attribute to an upstream
# package — which it does via the `# renovate:` comment directly above
# the pin. A pin added without one is silently invisible to automation:
# it never moves again, and nothing reports that. This script is copied
# verbatim into every project generated from this template, so one
# unbumpable pin propagates everywhere.
#
# LIVENESS PASS (needs the network, never fails on a network problem).
# Vendors retire release assets, rename repositories and move hosts, and
# nothing in the repo notices: the first symptom is a cold-start install
# failing on a fresh machine, which is precisely the moment there is no
# working setup left to debug it with. The URL list is never hardcoded
# here — it is extracted from the sources on every run, so a URL added
# tomorrow is covered without editing this file.
#
# The two passes are graded differently on purpose. The annotation pass
# reads only the tree, so a failure there is always the commit's fault.
# The liveness pass depends on a network this script does not own, so a
# refused connection, a DNS failure or a timeout is reported as SKIP and
# changes no exit code — a laptop on a plane and a consumer's CI behind
# a proxy must not see a red build. A served HTTP error status is a
# different thing: the vendor answered, and the answer is that the
# pinned artifact is gone. That fails.
#
# This reports; it never repairs. Re-pinning means picking a new version
# and a new checksum, which is a human decision, not something a cron
# job may do.
#
# Usage: check-pinned-urls.sh [path...]   (default: scripts/ci-install-tools.sh, the file renovate.json reads)
# Exit:  0 every pin annotated and every URL answered
#        1 a pin lacks an annotation, or a URL is DEAD
#        2 a path argument does not exist
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  targets=("$repo_root/scripts/ci-install-tools.sh")
  if [ ! -e "${targets[0]}" ]; then
    echo "check-pinned-urls: no files to check"
    exit 0
  fi
fi
for target in "${targets[@]}"; do
  if [ ! -e "$target" ]; then
    echo "check-pinned-urls: no such path: $target" >&2
    exit 2
  fi
done

files=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  files+=("$file")
done <<<"$(find "${targets[@]}" -type f | sort)"

if [ ${#files[@]} -eq 0 ]; then
  echo "no files to check"
  exit 0
fi

# ---------------------------------------------------------------- pass 1
# Only `*_VERSION` entries name an upstream release; the `*_SHA256` line
# under a pin rides along in the same renovate.json match.
# Must match the customManagers regex in renovate.json: datasource and
# depName on the annotation, and the quoted "${NAME:-value}" pin form.
ann_re='^# renovate: datasource=[a-z.-]+ depName=[^[:space:]]+'
pin_re='^[A-Z_]+_VERSION="\$\{[A-Z_]+_VERSION:-[^}"]+\}"'
unannotated=0
# Pass 2 probes only these. A file with no pin downloads nothing this
# template pins; its URLs are the project's own (a lab API, a docs page),
# and an HTTP error there says nothing about a retired release asset.
pinned_files=()
for file in "${files[@]}"; do
  prev=""
  lineno=0
  want_sha=""
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # A version-only Renovate bump leaves a stale digest and breaks every
    # install, so a non-npm pin needs its digest in the form renovate.json
    # matches, on the very next line.
    if [ -n "$want_sha" ]; then
      sha_re="^${want_sha}_SHA256=\"\\$\\{${want_sha}_SHA256:-[0-9a-f]{64}\\}\"$"
      if ! [[ "$line" =~ $sha_re ]]; then
        echo "${file#"$repo_root"/}:$lineno: ${want_sha}_VERSION needs" \
          "${want_sha}_SHA256=\"\${${want_sha}_SHA256:-<64 hex>}\" on the next line" >&2
        unannotated=$((unannotated + 1))
      fi
      want_sha=""
    fi
    if [[ "$line" =~ ^([A-Z_]+)_VERSION= ]]; then
      name="${BASH_REMATCH[1]}_VERSION"
      prefix="${BASH_REMATCH[1]}"
      [ "$file" = "${last_pinned:-}" ] || { pinned_files+=("$file"); last_pinned=$file; }
      if ! [[ "$prev" =~ $ann_re && "$line" =~ $pin_re ]]; then
        echo "${file#"$repo_root"/}:$lineno: $name is not annotated in the" \
          "form renovate.json parses (see below)" >&2
        unannotated=$((unannotated + 1))
      elif [ "$prev" != "# renovate: datasource=npm depName=@biomejs/cli-linux-x64" ]; then
        want_sha=$prefix
      fi
    fi
    prev="$line"
  done <"$file"
  if [ -n "$want_sha" ]; then
    echo "${file#"$repo_root"/}: ${want_sha}_VERSION has no ${want_sha}_SHA256 line" >&2
    unannotated=$((unannotated + 1))
  fi
done

# The installer reads only the *.txt lock. A Renovate PR whose re-lock
# failed bumps the *.in alone and would install the old version silently.
for in_file in "$repo_root"/scripts/ci-requirements/*.in; do
  [ -f "$in_file" ] || continue
  while IFS= read -r req; do
    [[ "$req" =~ ^[A-Za-z0-9._-]+==[^[:space:]]+$ ]] || continue
    if ! grep -qiE "^${req//./[.]}( |$)" "${in_file%.in}.txt" 2>/dev/null; then
      echo "${in_file#"$repo_root"/}: $req is not in ${in_file##*/}'s .txt lock;" \
        "re-run the uv pip compile command in its header" >&2
      unannotated=$((unannotated + 1))
    fi
  done <"$in_file"
done

if [ "$unannotated" -ne 0 ]; then
  cat >&2 <<'EOF'

Every version pin must carry an annotation directly above it, e.g.

  # renovate: datasource=github-release-attachments depName=owner/repo
  EXAMPLE_VERSION="${EXAMPLE_VERSION:-v1.2.3}"
  EXAMPLE_SHA256="${EXAMPLE_SHA256:-<64 hex>}"

Python tools pin in scripts/ci-requirements/*.in instead. See the
customManagers entry in renovate.json.
EOF
else
  echo "OK ${#files[@]} file(s): every version pin is annotated"
fi

# ---------------------------------------------------------------- pass 2
# Hosts that are cited as prose in a comment, not downloaded from. Their
# pages get reorganised on the vendor's schedule and a 404 there breaks
# nothing.
skip_hosts=(docs.github.com docs.renovatebot.com conventionalcommits.org
  www.conventionalcommits.org semver.org keepachangelog.com)
# The placeholder in the commit-trailer examples, which is not a repo.
skip_prefixes=(https://github.com/org/repo)

# Assignments are resolved in file order against everything assigned
# above them, because a download URL is normally accumulated across two
# or three lines (`gl="https://…/download"`, then `gl="$gl/v$VERSION"`).
# A per-file substitution pass keeps this hermetic: no rendering, no
# config, no shell evaluation of a file we are only inspecting.
expand() {
  local url=$1 map=$2 name value
  while IFS='=' read -r name value; do
    [ -n "$name" ] || continue
    url=${url//\$\{$name\}/$value}
    url=${url//\$\{$name#v\}/${value#v}}
    url=${url//\$$name/$value}
  done <<<"$map"
  printf '%s' "$url"
}

assignment_map() {
  local map="" name value
  # `NAME="value"` (sh), `export NAME=value`, `$Name = 'value'` (pwsh).
  while IFS='=' read -r name value; do
    [ -n "$name" ] || continue
    # `NAME="${NAME:-1.2.3}"` is the pin idiom: the default is the pin.
    # shellcheck disable=SC2016
    case $value in
      '${'*':-'*'}')
        value=${value#*:-}
        value=${value%\}}
        ;;
      *) value=$(expand "$value" "$map") ;;
    esac
    # Newest first, so expand() applies the LAST assignment of a name.
    # A download URL is accumulated (`gl="…/download"`, then
    # `gl="$gl/v$VERSION"`), and only the final value is downloaded from.
    map="$name=$value"$'\n'"$map"
  done <<<"$(sed -nE \
    "s/^[[:space:]]*(export[[:space:]]+)?\\\$?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*[\"']?([^\"'#[:space:]]+)[\"']?.*/\\2=\\3/p" \
    "$1")"
  printf '%s' "$map"
}

is_skipped() {
  local url=$1 host entry
  host=${url#*://}
  host=${host%%/*}
  host=${host%%:*}
  for entry in "${skip_hosts[@]}"; do
    [ "$host" = "$entry" ] && return 0
  done
  for entry in "${skip_prefixes[@]}"; do
    case $url in "$entry"*) return 0 ;; esac
  done
  return 1
}

# A bare `…/releases/download/<tag>` directory always 404s on GitHub:
# only the assets under it are served. The tag page is what tells us
# whether the pinned release still exists, and it is what a human
# re-pins against.
probe_url() {
  case $1 in
    https://github.com/*/releases/download/*)
      local rest=${1#*/releases/download/}
      case $rest in
        */*) printf '%s' "$1" ;; # a real asset path, check it directly
        *) printf '%s' "${1%/releases/download/*}/releases/tag/$rest" ;;
      esac
      ;;
    *) printf '%s' "$1" ;;
  esac
}

# HEAD is the cheap probe, but plenty of CDNs answer it with 405 or 403
# while serving the artifact fine, so a rejected HEAD falls back to
# asking for the first byte rather than downloading the whole release.
#
# Prints `live`, `dead` or `skip: <reason>`. curl exit 22 means the
# server answered with an HTTP error status; every other failure is the
# transport, which this script does not judge. `--retry` is left off on
# purpose: it would turn an offline run into minutes of backoff.
probe() {
  local url code
  url=$(probe_url "$1")
  curl -fsS --head --max-time 15 -o /dev/null "$url" 2>/dev/null && {
    printf 'live'
    return
  }
  code=0
  curl -fsS --max-time 15 -r 0-0 -o /dev/null "$url" 2>/dev/null || code=$?
  case $code in
    0) printf 'live' ;;
    22) printf 'dead' ;;
    *) printf 'skip: curl exit %s' "$code" ;;
  esac
}

checkable=()
for file in ${pinned_files[@]+"${pinned_files[@]}"}; do
  map=$(assignment_map "$file")
  # The `$`, `{` and `}` in the class keep an interpolated URL whole so
  # expand() can substitute it, and the leading alternation catches a
  # URL whose scheme and host live in a variable. The regex is
  # deliberately literal.
  # shellcheck disable=SC2016
  while IFS= read -r match; do
    [ -n "$match" ] || continue
    url=$(expand "$match" "$map")
    # The character class cannot capture a quote or a comma, so the only
    # trailing punctuation left to shed is sentence-final, plus the `}`
    # that closes a `${VAR:-https://…}` default the class ran into.
    while [ -n "$url" ]; do
      case $url in
        *[.,\;:\}]) url=${url%?} ;;
        *) break ;;
      esac
    done
    case $url in
      http://* | https://*) ;;
      *) continue ;; # a local path built from a variable, not a URL
    esac
    # A base a download URL is accumulated onto serves nothing on its
    # own: the tag and the asset name are appended elsewhere. On
    # raw.githubusercontent.com a real file needs owner/repo/ref/path.
    reason=""
    case $url in
      *'$'* | *'{'*) reason="unresolved interpolation" ;;
      */ | */releases/download) reason="prefix only" ;;
      https://raw.githubusercontent.com/*/*/*/?*) ;;
      https://raw.githubusercontent.com/*) reason="prefix only" ;;
    esac
    if [ -n "$reason" ]; then
      echo "SKIP $url ($reason)"
      continue
    fi
    if is_skipped "$url"; then
      echo "SKIP $url (documentation)"
      continue
    fi
    checkable+=("$url")
    # Two sources, so an accumulated URL is read once and whole: the
    # resolved assignment values (the `gl="$gl/v$VERSION"` chain, whose
    # last value is the one downloaded from) and the URLs written
    # inline on every other line. Assignment lines are dropped from the
    # second source, or the chain would be counted twice and the second
    # count would append the tag to an already-tagged base.
  done <<<"$(
    {
      cut -d= -f2- <<<"$map"
      sed -E "/^[[:space:]]*(export[[:space:]]+)?\\\$?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/d" "$file"
    } | grep -hoE \
      '(https?://|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/)[a-zA-Z0-9.:/_%@?=&{}$~#-]*' \
      || true
  )"
done

dead=0
skipped=0
if [ ${#checkable[@]} -eq 0 ]; then
  echo "no pinned URLs to check"
else
  while IFS= read -r url; do
    result=$(probe "$url")
    case $result in
      live) echo "OK $url" ;;
      dead)
        echo "DEAD $url"
        dead=$((dead + 1))
        ;;
      *)
        echo "SKIP $url ($result)"
        skipped=$((skipped + 1))
        ;;
    esac
  done <<<"$(printf '%s\n' "${checkable[@]}" | sort -u)"
fi

if [ "$skipped" -ne 0 ]; then
  echo "NOTICE liveness check skipped for $skipped URL(s):" \
    "the network did not answer. Annotations were still enforced."
fi
if [ "$dead" -ne 0 ]; then
  echo "$dead pinned URL(s) answered with an HTTP error" >&2
fi
if [ "$unannotated" -ne 0 ] || [ "$dead" -ne 0 ]; then
  exit 1
fi
