#!/usr/bin/env bash
set -euo pipefail

ROOT="${CRAFT_WIKI_ARCHIVE_ROOT:-$(pwd)/craft-archive/documentation/craft-wiki}"
REPO_DIR="${CRAFT_WIKI_REPO_DIR:-$ROOT/source}"
DIST_DIR="${CRAFT_WIKI_DIST_DIR:-$ROOT/dist}"
VIEWER_SRC="${CRAFT_WIKI_VIEWER_SRC:-$(pwd)/internal/viewer}"
HOST="${CRAFT_WIKI_HOST:-127.0.0.1}"
PORT="${CRAFT_WIKI_PORT:-42420}"

usage() {
  cat >&2 <<'EOF'
Usage: archive-wiki.sh <clone|build|launcher|archive|launch>

Actions:
  clone     Clone the Craft Wiki source repository.
  build     Build the static site to the archive dist directory.
  launcher  Cross-compile the local viewer binaries for common targets.
  archive   Build and package the wiki archive with provenance.
  launch    Print the exact host-specific launch command.

Environment:
  CRAFT_WIKI_ARCHIVE_ROOT     Destination root for the wiki archive (default: ./craft-archive/documentation/craft-wiki)
  CRAFT_WIKI_REPO_DIR         Source clone directory (default: <archive_root>/source)
  CRAFT_WIKI_DIST_DIR         Static site output directory (default: <archive_root>/dist)
  CRAFT_WIKI_VIEWER_SRC       Go viewer source directory (default: ./internal/viewer)
  CRAFT_WIKI_HOST             Host to bind (default: 127.0.0.1)
  CRAFT_WIKI_PORT             Default viewer port (default: 42420)
EOF
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

clone_repo() {
  mkdir -p "$(dirname "$REPO_DIR")"
  if [ -d "$REPO_DIR/.git" ]; then
    git -c core.longpaths=true -C "$REPO_DIR" fetch --depth 20 --tags origin
    git -c core.longpaths=true -C "$REPO_DIR" checkout main
  else
    git clone -c core.longpaths=true --depth 20 --branch main https://github.com/storytold/craft-wiki.git "$REPO_DIR"
  fi
}

build_wiki() {
  clone_repo
  mkdir -p "$DIST_DIR"
  cd "$REPO_DIR"
  npm ci
  npm run build
  rm -rf "$DIST_DIR"
  cp -R dist "$DIST_DIR"
}

build_viewers() {
  local out_root="$ROOT/launchers"
  mkdir -p "$out_root"

  build_target() {
    local goos="$1"
    local goarch="$2"
    local target_name="$3"
    local out="$out_root/$target_name"
    mkdir -p "$out"

    local output="$out/craft-wiki-viewer"
    if [ "$goos" = "windows" ]; then
      output="$out/craft-wiki-viewer.exe"
    fi

    CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" go build -o "$output" "$VIEWER_SRC"
    echo "Built $output"
  }

  build_target windows amd64 windows-amd64
  build_target windows arm64 windows-arm64
  build_target darwin amd64 darwin-amd64
  build_target darwin arm64 darwin-arm64
  build_target linux amd64 linux-amd64
  build_target linux arm64 linux-arm64
}

archive_wiki() {
  build_started_at="$(timestamp)"
  build_wiki
  built_at="$(timestamp)"
  build_viewers

  commit="$(git -C "$REPO_DIR" rev-parse HEAD)"
  branch="$(git -C "$REPO_DIR" rev-branch 2>/dev/null || echo main)"
  node_version="$(node --version 2>/dev/null || echo unknown)"
  npm_lock_sha="$(sha256sum "$REPO_DIR/package-lock.json" 2>/dev/null | awk '{print $1}' || echo unknown)"
  dist_sha="$(find "$DIST_DIR" -type f -exec sha256sum {} + 2>/dev/null | sha256sum | awk '{print $1}' || echo unknown)"

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
viewer_binary_sha256 = "unknown"
EOF

  printf 'Archived wiki at %s\n' "$ROOT"
}

launch_help() {
  if [ ! -d "$DIST_DIR" ]; then
    echo "Missing dist directory: $DIST_DIR" >&2
    exit 1
  fi
  platform="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m | tr '[:upper:]' '[:lower:]')"
  printf 'Use: ./craft-archive/documentation/craft-wiki/launchers/%s/craft-wiki-viewer --root "%s" --host "%s" --port "%s"\n' "$platform" "$DIST_DIR" "$HOST" "$PORT"
}

case "${1:-}" in
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
