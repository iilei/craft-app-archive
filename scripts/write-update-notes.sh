#!/usr/bin/env bash
# Write UPDATE.txt into a finished archive: the exact mise command that refreshes
# it, the tooling commit needed to reproduce it, and how someone who only has
# the archive gets the tooling.
# Usage: write-update-notes.sh <archive dir> <final destination> <verify signatures: true|false>
# Reads the mise task's usage_* variables for the flags of the current run.
set -euo pipefail

archive_dir="$1"
destination="$2"
verify_signatures="$3"
repo_dir="$(pwd -P)"

# Flags in mise.toml order: <flag> <default>. Only flags that differ from the
# default are written, using the negated --no-<flag> form for default-on ones.
flags=(
  wiki true
  macos true
  windows-x64 true
  windows-arm64 false
  windows-x86 false
  linux-x86_64-deb true
  linux-x86_64-appimage false
  linux-x86_64-flatpak false
  linux-x86_64-rpm false
  linux-x86_64-tar-gz false
  linux-x86_64-pkg-tar-zst false
  linux-aarch64-deb false
  linux-aarch64-appimage false
  linux-aarch64-flatpak false
  linux-aarch64-rpm false
  linux-aarch64-tar-gz false
  linux-aarch64-pkg-tar-zst false
  linux-riscv64-deb false
  linux-riscv64-rpm false
  linux-riscv64-tar-gz false
)


readonly REPO_URL="https://github.com/iilei/craft-app-archive"

# Options of this run that differ from the defaults (destination excluded).
options=()
if [[ "${usage_depth:-20}" != 20 ]]; then
  options+=(--depth "$usage_depth")
fi
if [[ "${usage_retries:-3}" != 3 ]]; then
  options+=(--retries "$usage_retries")
fi
if [[ "${usage_retry_delay:-5}" != 5 ]]; then
  options+=(--retry-delay "$usage_retry_delay")
fi
if [[ -n "${usage_wiki_targets:-}" && "${usage_wiki:-true}" == true ]]; then
  options+=(--wiki-targets "$usage_wiki_targets")
fi
for ((i = 0; i < ${#flags[@]}; i += 2)); do
  flag="${flags[i]}" default="${flags[i + 1]}"
  var="usage_${flag//-/_}"
  value="${!var:-$default}"
  [[ "$value" == "$default" ]] && continue
  if [[ "$value" == true ]]; then
    options+=("--$flag")
  else
    options+=("--no-$flag")
  fi
done
if [[ "$verify_signatures" != true ]]; then
  options+=(--no-verify-signatures)
fi
quoted_options="$( ((${#options[@]})) && printf ' %q' "${options[@]}" || true)"

command="mise -C $(printf '%q' "$repo_dir") run archive --destination $(printf '%q' "$destination") --overwrite$quoted_options"
# A custom app list is passed by environment, so it has to be part of the command.
if [[ -n "${CRAFT_APPS_MANIFEST:-}" ]]; then
  manifest="$(cd "$(dirname "$CRAFT_APPS_MANIFEST")" && pwd -P)/$(basename "$CRAFT_APPS_MANIFEST")"
  command="CRAFT_APPS_MANIFEST=$(printf '%q' "$manifest") $command"
fi

commit="unknown" dirty=""
if git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
  commit="$(git -C "$repo_dir" rev-parse HEAD)"
  [[ -z "$(git -C "$repo_dir" status --porcelain --untracked-files=no)" ]] || dirty=" (with uncommitted changes)"
fi
mise_version="$(mise --version 2>/dev/null | awk '{print $1}' || true)"

cat > "$archive_dir/UPDATE.txt" <<EOF
Craft app archive - how to update

This archive was created with craft-app-archive, a mise task that clones the
Craft apps' sources and downloads their latest release packages with
provenance:

  $REPO_URL

Update on the machine that created it
-------------------------------------

To refresh this archive with the latest releases, using the same options as
the run that created it, run:

  $command

The command rebuilds the archive in a temporary directory and replaces this
one only after the run succeeds. If the repository or this archive has moved,
adjust the -C path or --destination; from inside the repository, -C can be
left out.

If a run stops partway (network trouble, GitHub rate limits), its progress is
kept: run the same command again with --resume added to continue it. Setting
GH_TOKEN to a GitHub token raises the API limit from 60 to 5000 requests per
hour.

Update a copy you were given
----------------------------

Everything needed is public. You need git, bash, curl and gpg (on Windows,
Git for Windows provides all four as Git Bash) and mise, the tool runner that
provides the task and its pinned tools:

  https://mise.jdx.dev/installing-mise.html

  Windows  winget install jdx.mise
  macOS    brew install mise
  Linux    curl -fsSL https://mise.run | sh

Then get the task and run it against your copy of this folder. Using this
folder's apps.txt keeps the same app list:

  git clone $REPO_URL.git
  cd craft-app-archive
  git checkout $commit   # optional: the exact tooling version used
  mise trust
  mise install
  CRAFT_APPS_MANIFEST=<this folder>/apps.txt mise run archive --destination <this folder> --overwrite$quoted_options

Replace <this folder> with the path to this archive folder. The repository's
README.md documents all options.

Tooling used for this archive
-----------------------------

  Repository  $REPO_URL
  Commit      $commit$dirty
  mise        ${mise_version:-unknown}
  App list    apps.txt (the list this archive was built from)

To reproduce the archive with the same tooling instead of the latest, check
out that commit before running the update:

  git -C $(printf '%q' "$repo_dir") checkout $commit

Per-app details (release, source commit, checksums, verification method) are
in each app's provenance.toml. If present, craft-wiki/ holds an offline copy of
the Craft Wiki: see craft-wiki/README.txt for how to open it.
EOF
