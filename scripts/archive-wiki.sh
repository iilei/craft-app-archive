#!/usr/bin/env bash
set -euo pipefail

# Outside the app archive's default craft-archive/, which `mise run archive
# --overwrite` replaces as a whole. REPO_DIR and DIST_DIR follow after options.
ROOT="${CRAFT_WIKI_ARCHIVE_ROOT:-$(pwd)/craft-wiki}"
VIEWER_SRC="${CRAFT_WIKI_VIEWER_SRC:-$(pwd)/internal/viewer}"
HOST="${CRAFT_WIKI_HOST:-127.0.0.1}"
PORT="${CRAFT_WIKI_PORT:-42420}"
TARGETS="${CRAFT_WIKI_TARGETS:-}"
# Same settings as the app archive's --retries / --retry-delay, which export them.
RETRIES="${CRAFT_RETRIES:-3}"
RETRY_DELAY="${CRAFT_RETRY_DELAY:-5}"
ALL_TARGETS=(windows-amd64 windows-arm64 darwin-amd64 darwin-arm64 linux-amd64 linux-arm64)

usage() {
  cat >&2 <<'EOF'
Usage: archive-wiki.sh <clone|build|launcher|archive|launch> [--destination PATH] [--targets LIST]

Actions:
  clone     Clone the Craft Wiki source repository.
  build     Build the static site into the archive documentation directory.
  launcher  Cross-compile the local viewer binaries for common targets.
  archive   Build and package the wiki archive with provenance.
  launch    Print the exact host-specific launch command.

Options:
  --destination PATH  Wiki archive directory (default: ./craft-wiki)
  --targets LIST  Comma-separated viewer targets for launcher/archive (default: all):
                  windows-amd64, windows-arm64, darwin-amd64, darwin-arm64,
                  linux-amd64, linux-arm64

Environment:
  CRAFT_WIKI_ARCHIVE_ROOT     Same as --destination (the option takes precedence)
  CRAFT_WIKI_REPO_DIR         Source clone directory (default: <archive_root>/source)
  CRAFT_WIKI_DIST_DIR         Static site output directory (default: <archive_root>/documentation)
  CRAFT_WIKI_VIEWER_SRC       Go viewer source directory (default: ./internal/viewer)
  CRAFT_WIKI_HOST             Host to bind (default: 127.0.0.1)
  CRAFT_WIKI_PORT             Default viewer port (default: 42420)
  CRAFT_WIKI_TARGETS          Same as --targets (the option takes precedence)
  CRAFT_RETRIES               Retries after a failed git or npm network step (default: 3)
  CRAFT_RETRY_DELAY           Seconds before the first retry; grows per attempt (default: 5)
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

case "$RETRIES$RETRY_DELAY" in
  *[!0-9]*|'') die "CRAFT_RETRIES and CRAFT_RETRY_DELAY must be non-negative integers" ;;
esac

# Run a command, retrying up to RETRIES times with a growing delay
# (RETRY_DELAY, 2x, 3x, ...). Usage: retry <description> <command...>
retry() {
  local description="$1" attempt=0 wait
  shift
  until "$@"; do
    if [ "$attempt" -ge "$RETRIES" ]; then
      echo "ERROR: $description failed after $((attempt + 1)) attempt(s)" >&2
      return 1
    fi
    attempt=$((attempt + 1))
    wait=$((RETRY_DELAY * attempt))
    echo "WARN: $description failed; retrying in ${wait}s ($attempt/$RETRIES)" >&2
    sleep "$wait"
  done
}

if command -v sha256sum >/dev/null 2>&1; then
  SHA256=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  SHA256=(shasum -a 256)
else
  SHA256=()
fi
sha256() { "${SHA256[@]}" "$@" | awk '{print $1}'; }

# Hash of a directory tree that depends only on relative paths and contents:
# one "<sha256>  ./<path>" line per file in byte order, hashed as a whole.
tree_sha256() {
  (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 "${SHA256[@]}") | sha256
}

# RFC 3339 time in the local zone (honours TZ), e.g. 2026-11-07T11:05:00+01:00.
# One date call keeps time and offset consistent; %z works with GNU and BSD date,
# while %:z is GNU-only, so the colon is inserted here. Falls back to UTC.
timestamp() {
  local now
  now="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  if [[ "$now" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$ ]]; then
    printf '%s:%s\n' "${now:0:${#now}-2}" "${now: -2}"
  else
    date -u '+%Y-%m-%dT%H:%M:%SZ'
  fi
}

# Resolve TARGETS (comma-separated) into SELECTED_TARGETS, validated and deduplicated.
select_targets() {
  local requested=() target known seen=" "
  SELECTED_TARGETS=()
  IFS=, read -r -a requested <<<"${TARGETS// /}"
  [ "${#requested[@]}" -gt 0 ] || requested=("${ALL_TARGETS[@]}")
  for target in "${requested[@]}"; do
    [ -n "$target" ] || continue
    for known in "${ALL_TARGETS[@]}"; do
      [ "$target" = "$known" ] && break
    done
    [ "$target" = "$known" ] || die "unknown target: $target (supported: ${ALL_TARGETS[*]})"
    case "$seen" in *" $target "*) continue ;; esac
    seen="$seen$target "
    SELECTED_TARGETS+=("$target")
  done
  [ "${#SELECTED_TARGETS[@]}" -gt 0 ] || die "no targets selected"
}

clone_repo() {
  mkdir -p "$(dirname "$REPO_DIR")"
  if [ -d "$REPO_DIR/.git" ]; then
    [ -z "$(git -c core.longpaths=true -C "$REPO_DIR" status --porcelain)" ] || die "local changes in clone prevent update: $REPO_DIR"
    retry "git fetch craft-wiki" git -c core.longpaths=true -C "$REPO_DIR" fetch --depth 20 --tags origin main
    git -c core.longpaths=true -C "$REPO_DIR" checkout -B main FETCH_HEAD
  else
    retry "git clone craft-wiki" clone_fresh
  fi
  # The reflog records the local git user's name and email; keep it out of the archive.
  git -C "$REPO_DIR" config --replace-all core.logAllRefUpdates false
  rm -rf -- "$REPO_DIR/.git/logs"
}

# A failed clone can leave a partial directory behind; start each attempt clean.
clone_fresh() {
  rm -rf -- "$REPO_DIR"
  git clone -c core.longpaths=true -c core.logAllRefUpdates=false --depth 20 --branch main https://github.com/storytold/craft-wiki.git "$REPO_DIR"
}

# npm ci downloads packages (and starts from a clean node_modules each time).
npm_ci() { (cd "$REPO_DIR" && npm ci); }

build_wiki() {
  clone_repo
  retry "npm ci" npm_ci
  (cd "$REPO_DIR" && npm run build)
  rm -rf "$DIST_DIR"
  # Archives built before the rename kept the site in dist/; drop that stale copy.
  if [ "$DIST_DIR" != "$ROOT/dist" ] && [ -d "$ROOT/dist" ] && [ -f "$ROOT/provenance.toml" ]; then
    rm -rf "$ROOT/dist"
  fi
  mkdir -p "$(dirname "$DIST_DIR")"
  cp -R "$REPO_DIR/dist" "$DIST_DIR"
}

build_viewers() {
  local out_root="$ROOT/launchers" target
  select_targets
  # Start clean so launchers/ holds exactly the binaries recorded in provenance.
  rm -rf "$out_root"
  mkdir -p "$out_root"
  VIEWER_TARGETS=()
  VIEWER_BINARIES=()

  build_target() {
    local goos="$1"
    local goarch="$2"
    local target_name="$3"
    local out="$out_root/$target_name"
    mkdir -p "$out"
    out="$(cd "$out" && pwd)"  # absolute, since go build runs from $VIEWER_SRC
    # -trimpath keeps local paths (home directory, toolchain location) out of the binary.

    local output="$out/craft-wiki-viewer"
    if [ "$goos" = "windows" ]; then
      output="$out/craft-wiki-viewer.exe"
    fi

    (cd "$VIEWER_SRC" && CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" go build -trimpath -o "$output" .)
    VIEWER_TARGETS+=("$target_name")
    VIEWER_BINARIES+=("$output")
    echo "Built $output"
  }

  for target in "${SELECTED_TARGETS[@]}"; do
    build_target "${target%-*}" "${target#*-}" "$target"
  done
  install_start_scripts
}

# Copy the double-click entry points to the archive root. They resolve every
# path from their own location, so the archive folder stays relocatable.
install_start_scripts() {
  local src="$VIEWER_SRC/start"
  cp "$src/start.sh" "$src/start.command" "$ROOT/"
  chmod +x "$ROOT/start.sh" "$ROOT/start.command"
  # cmd.exe expects CRLF line endings regardless of how the template was checked out.
  awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$src/start.cmd" > "$ROOT/start.cmd"
}

archive_wiki() {
  [ "${#SHA256[@]}" -gt 0 ] || die "sha256sum or shasum is required"
  build_started_at="$(timestamp)"
  build_wiki
  built_at="$(timestamp)"
  build_viewers

  commit="$(git -C "$REPO_DIR" rev-parse HEAD)"
  branch="$(git -C "$REPO_DIR" symbolic-ref --short HEAD)"
  node_version="$(node --version 2>/dev/null || echo unknown)"
  npm_lock_sha="$(sha256 "$REPO_DIR/package-lock.json")"
  [ -n "$(find "$DIST_DIR" -type f -print -quit)" ] || die "no files in documentation directory: $DIST_DIR"
  dist_sha="$(tree_sha256 "$DIST_DIR")"

  cat > "$ROOT/provenance.toml" <<EOF
schema_version = 1
name = "Craft Wiki"
slug = "craft-wiki"
group = "documentation"
category = "wiki"
repository = "storytold/craft-wiki"
repository_url = "https://github.com/storytold/craft-wiki.git"
source_ref = "$branch"
source_ref_type = "branch"
commit = "$commit"
clone_depth = 20
shallow = true
build_tool = "npm"
node_version = "$node_version"
build_command = "npm ci && npm run build"
build_started_at = "$build_started_at"
built_at = "$built_at"
lockfile_sha256 = "$npm_lock_sha"
dist_sha256 = "$dist_sha"
rendered_output = "static-site"
viewer_host = "127.0.0.1"
viewer_port = 42420
viewer_binary_name = "craft-wiki-viewer"
EOF

  local i root_abs
  root_abs="$(cd "$ROOT" && pwd)"
  for i in "${!VIEWER_BINARIES[@]}"; do
    printf '\n[[viewer_binaries]]\ntarget = "%s"\npath = "%s"\nsha256 = "%s"\n' \
      "${VIEWER_TARGETS[$i]}" "${VIEWER_BINARIES[$i]#"$root_abs"/}" "$(sha256 "${VIEWER_BINARIES[$i]}")"
  done >> "$ROOT/provenance.toml"

  write_readme "$root_abs"
  printf 'Archived wiki at %s\n' "$ROOT"
}

write_readme() {
  local root_abs="$1" i
  {
    cat <<EOF
Craft Wiki - offline archive

Source: storytold/craft-wiki, branch $branch, commit $commit
Built:  $built_at

To open the wiki, start it from this folder:

  Windows  double-click start.cmd
  macOS    double-click start.command
  Linux    run ./start.sh

The folder is self-contained: move or copy it anywhere (another disk, a USB
stick, another machine) and the start scripts keep working. Viewers included:

EOF
    for i in "${!VIEWER_BINARIES[@]}"; do
      printf '  %-14s %s\n' "${VIEWER_TARGETS[$i]}" "${VIEWER_BINARIES[$i]#"$root_abs"/}"
    done
    cat <<'EOF'

The viewer serves the wiki from documentation/ on http://127.0.0.1:42420
(loopback only) and opens your browser. Options, passed to the start scripts or the viewer directly:

  --port <n>   port 0-65535; use --port 0 if 42420 is taken
  --root <dir> site directory (found automatically next to launchers/)
  --host <h>   127.0.0.1 or localhost only
  --no-open    do not open the browser

This is a static, read-only copy: sign-in and the CMS of the live site do
not work offline. Keep documentation/ next to launchers/ when copying the
archive.

If the browser was already open, the wiki opens as a new tab there but may
stay in the background (GNOME on Wayland does not let it come to the front).
Switch to the browser, or open http://127.0.0.1:42420 yourself (with --port,
use the address the viewer prints).

On macOS, a downloaded archive may be blocked as unsigned; allow it under
System Settings > Privacy & Security, or run in this folder:
  xattr -dr com.apple.quarantine .

provenance.toml records the source commit, build details, the rendered
site's hash and the SHA-256 of every viewer binary.
EOF
  } > "$ROOT/README.txt"
}

launch_help() {
  [ -d "$DIST_DIR" ] || die "missing documentation directory: $DIST_DIR"
  local goos goarch binary
  case "$(uname -s)" in
    Linux) goos=linux ;;
    Darwin) goos=darwin ;;
    MINGW*|MSYS*|CYGWIN*) goos=windows ;;
    *) die "unsupported OS: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) goarch=amd64 ;;
    aarch64|arm64) goarch=arm64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
  binary="$ROOT/launchers/$goos-$goarch/craft-wiki-viewer"
  if [ "$goos" = windows ]; then
    binary="$binary.exe"
  fi
  [ -f "$binary" ] || die "no viewer for $goos-$goarch: $binary (build it with: launcher --targets $goos-$goarch)"
  printf 'Use: %q --root %q --host %q --port %q\n' "$binary" "$DIST_DIR" "$HOST" "$PORT"
}

action="${1:-}"
[ "$#" -gt 0 ] && shift
while [ "$#" -gt 0 ]; do
  case "$1" in
    --targets) TARGETS="${2:?--targets requires a comma-separated list}"; shift 2 ;;
    --targets=*) TARGETS="${1#*=}"; shift ;;
    --destination) ROOT="${2:?--destination requires a path}"; shift 2 ;;
    --destination=*) ROOT="${1#*=}"; [ -n "$ROOT" ] || die "--destination requires a path"; shift ;;
    *) usage; die "unrecognized argument: $1" ;;
  esac
done
REPO_DIR="${CRAFT_WIKI_REPO_DIR:-$ROOT/source}"
DIST_DIR="${CRAFT_WIKI_DIST_DIR:-$ROOT/documentation}"

case "$action" in
  clone)
    clone_repo
    ;;
  build)
    build_wiki
    ;;
  launcher)
    build_viewers
    ;;
  archive)
    archive_wiki
    ;;
  launch)
    launch_help
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
