#!/usr/bin/env bash
set -euo pipefail

ROOT="${CRAFT_ARCHIVE_DIR:-craft-archive}"
TARGET_ROOT="$ROOT"
TEMP_ROOT=""
MANIFEST="${CRAFT_APPS_MANIFEST:-apps.tsv}"
API="https://api.github.com"
DEPTH=20
VERIFY_SIGNATURES=true
WANT_MACOS=true
WANT_WINDOWS_X64=true
WANT_WINDOWS_ARM64=false
WANT_WINDOWS_X86=false
OVERWRITE=false
AUTH=()
[[ -n "${GH_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer $GH_TOKEN")

# New Linux targets are opt-in and kept independent from the default x86_64 Debian package.
declare -A ASSET_SELECTION=(
  [linux-x86_64-deb]=true
  [linux-x86_64-appimage]=false
  [linux-x86_64-flatpak]=false
  [linux-x86_64-rpm]=false
  [linux-x86_64-tar-gz]=false
  [linux-x86_64-pkg-tar-zst]=false
  [linux-aarch64-deb]=false
  [linux-aarch64-appimage]=false
  [linux-aarch64-flatpak]=false
  [linux-aarch64-rpm]=false
  [linux-aarch64-tar-gz]=false
  [linux-aarch64-pkg-tar-zst]=false
  [linux-riscv64-deb]=false
  [linux-riscv64-rpm]=false
  [linux-riscv64-tar-gz]=false
)

usage() {
  cat >&2 <<'EOF'
Usage: archive-craft-apps.sh [options]

Options:
  --depth N                       Git shallow clone depth (default: 20)
  --destination PATH              Archive root directory (default: craft-archive)
  --overwrite                     Replace an existing archive directory
  --macos true|false             macOS installer download (default: true)
  --windows-x64 true|false       Windows x64 download (default: true)
  --windows-arm64 true|false     Windows ARM64 download (default: false)
  --windows-x86 true|false       Windows x86 download (default: false)
  --asset key true|false         Linux asset selector, e.g. --asset linux-aarch64-deb true
  --verify-signatures true|false Verify available release signatures (default: true)
  --no-verify-signatures         Disable signature verification
  -h, --help                     Show this help

Environment:
  CRAFT_ARCHIVE_DIR             Output root directory (default: craft-archive)
  CRAFT_APPS_MANIFEST           App manifest path (default: apps.tsv)
  GH_TOKEN                     GitHub API token (optional)
  CRAFT_GPG_KEY_FILE           Public key file for release verification
  CRAFT_GPG_FINGERPRINT        Expected GPG fingerprint for the trusted release key
  NO_VERIFY_SIGNATURE           Env opt-out: set to 1/true/yes to disable verification
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
q() { printf '%s' "$1" | jq -Rs .; }
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "sha256sum oder shasum ist erforderlich"
  fi
}
fetch_json() {
  curl -fsSL --retry 3 "${AUTH[@]}" -H 'Accept: application/vnd.github+json' "$1"
}
asset_url() {
  local body="$1" pattern="$2"
  jq -r --arg re "$pattern" '[.assets[] | select(.name | test($re; "i"))][0].browser_download_url // empty' <<<"$body"
}
asset_name() {
  local body="$1" pattern="$2"
  jq -r --arg re "$pattern" '[.assets[] | select(.name | test($re; "i"))][0].name // empty' <<<"$body"
}

bool_value() {
  local value="$1" name="$2"
  case "$value" in
    true|false) printf '%s\n' "$value" ;;
    *) die "$name muss true oder false sein" ;;
  esac
}

parse_bool_arg() {
  local arg="$1" value="$2" name="$3"
  if [[ "$arg" == "--no-"* ]]; then
    printf '%s\n' false
    return
  fi
  bool_value "$value" "$name"
}

while (($#)); do
  case "$1" in
    --destination)
      ROOT="${2:?--destination requires a path}"
      TARGET_ROOT="$ROOT"
      shift 2 ;;
    --destination=*)
      ROOT="${1#*=}"
      TARGET_ROOT="$ROOT"
      [[ -n "$ROOT" ]] || die "--destination requires a path"
      shift ;;
    --overwrite)
      OVERWRITE=true
      shift ;;
    --depth)
      DEPTH="${2:?--depth requires a value}"; shift 2 ;;
    --macos)
      WANT_MACOS="$(parse_bool_arg "$1" "${2:?--macos requires true or false}" "--macos")"; shift 2 ;;
    --windows-x64)
      WANT_WINDOWS_X64="$(parse_bool_arg "$1" "${2:?--windows-x64 requires true or false}" "--windows-x64")"; shift 2 ;;
    --windows-arm64)
      WANT_WINDOWS_ARM64="$(parse_bool_arg "$1" "${2:?--windows-arm64 requires true or false}" "--windows-arm64")"; shift 2 ;;
    --windows-x86)
      WANT_WINDOWS_X86="$(parse_bool_arg "$1" "${2:?--windows-x86 requires true or false}" "--windows-x86")"; shift 2 ;;
    --asset)
      key="${2:?--asset requires a target key}"; value="${3:?--asset requires true or false}"; value="$(bool_value "$value" "$key")"; ASSET_SELECTION["$key"]="$value"; shift 3 ;;
    --verify-signatures)
      VERIFY_SIGNATURES="$(parse_bool_arg "$1" "${2:?--verify-signatures requires true or false}" "--verify-signatures")"; shift 2 ;;
    --no-verify-signatures)
      VERIFY_SIGNATURES=false; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      usage; die "unrecognized argument: $1" ;;
  esac
done

# Environment opt-out must override the flag default.
case "${NO_VERIFY_SIGNATURE:-}" in
  1|true|yes|on|TRUE|YES|ON)
    VERIFY_SIGNATURES=false ;;
esac

[[ "$DEPTH" =~ ^[1-9][0-9]*$ ]] || die "depth muss eine positive ganze Zahl sein: $DEPTH"
for value in "$WANT_MACOS" "$WANT_WINDOWS_X64" "$WANT_WINDOWS_ARM64" "$WANT_WINDOWS_X86" "$VERIFY_SIGNATURES"; do
  [[ "$value" == true || "$value" == false ]] || die "boolean options must be true or false"
done
for value in "${ASSET_SELECTION[@]}"; do
  [[ "$value" == true || "$value" == false ]] || die "asset selection values must be true or false"
done

command -v git >/dev/null || die "git wird benötigt"
command -v curl >/dev/null || die "curl wird benötigt"
command -v jq >/dev/null || die "jq wird benötigt (mise install)"
[[ -f "$MANIFEST" ]] || die "Manifest fehlt: $MANIFEST"

if [[ -e "$TARGET_ROOT" ]]; then
  if [[ "$OVERWRITE" == true ]]; then
    mkdir -p "$(dirname "$TARGET_ROOT")"
    TEMP_ROOT="$(mktemp -d "$(dirname "$TARGET_ROOT")/.$(basename "$TARGET_ROOT").tmp.XXXXXX")"
    ROOT="$TEMP_ROOT"
  else
    die "destination exists: $TARGET_ROOT (pass --overwrite to replace it)"
  fi
else
  mkdir -p "$(dirname "$TARGET_ROOT")"
  if [[ "$OVERWRITE" == true ]]; then
    TEMP_ROOT="$(mktemp -d "$(dirname "$TARGET_ROOT")/.$(basename "$TARGET_ROOT").tmp.XXXXXX")"
    ROOT="$TEMP_ROOT"
  else
    mkdir -p "$TARGET_ROOT"
    ROOT="$TARGET_ROOT"
  fi
fi

cleanup_temp_root() {
  if [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]]; then
    rm -rf -- "$TEMP_ROOT"
  fi
}
trap cleanup_temp_root EXIT

if [[ "$VERIFY_SIGNATURES" == true ]]; then
  command -v gpg >/dev/null || die "gpg wird für Signaturprüfung benötigt"
  [[ -f "${CRAFT_GPG_KEY_FILE:-}" ]] || die "setze CRAFT_GPG_KEY_FILE auf einen unabhängig beschafften, vertrauenswürdigen Release-Key"
  [[ -n "${CRAFT_GPG_FINGERPRINT:-}" ]] || die "setze CRAFT_GPG_FINGERPRINT auf den unabhängig verifizierten Fingerprint"
  GNUPGHOME_TMP="$(mktemp -d)"
  chmod 700 "$GNUPGHOME_TMP"
  export GNUPGHOME="$GNUPGHOME_TMP"
  trap 'rm -rf "$GNUPGHOME_TMP"; cleanup_temp_root' EXIT
  gpg --batch --quiet --import "$CRAFT_GPG_KEY_FILE"
  expected_fpr="$(printf '%s' "$CRAFT_GPG_FINGERPRINT" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
  imported_fpr="$(gpg --batch --with-colons --fingerprint | awk -F: '$1=="fpr" {print toupper($10); exit}')"
  [[ "$imported_fpr" == "$expected_fpr" ]] || die "der importierte GPG-Key-Fingerprint stimmt nicht mit CRAFT_GPG_FINGERPRINT überein"
fi

verify_signature() {
  local signature="$1" data="$2"
  local status
  status="$(gpg --batch --status-fd 1 --verify "$signature" "$data" 2>/dev/null || true)"
  # VALIDSIG lists the signing (sub)key first and the primary key last; pin the primary.
  awk -v fpr="$expected_fpr" '$1=="[GNUPG:]" && $2=="VALIDSIG" && toupper($NF)==fpr {ok=1} END {exit !ok}' <<<"$status" || die "GPG-Signatur ungültig oder nicht vom gepinnten Schlüssel: $data"
}

while IFS=$'\t' read -r group category slug display repo; do
  [[ -z "${repo:-}" || "$group" == \#* ]] && continue
  category="${category# }"; category="${category% }"
  slug="${slug# }"; slug="${slug% }"
  dest="$ROOT/$group"
  [[ -n "$category" ]] && dest="$dest/$category"
  dest="$dest/$slug"
  repo_dir="$dest/source"
  mkdir -p "$dest"
  echo "==> $display ($repo)"

  repo_json="$(fetch_json "$API/repos/$repo")" || die "Repository nicht erreichbar: $repo"
  release=""
  if release="$(fetch_json "$API/repos/$repo/releases/latest" 2>/dev/null)"; then
    [[ "$(jq -r '.tag_name // empty' <<<"$release")" ]] || release=""
  fi

  if [[ -n "$release" ]]; then
    source_ref="$(jq -r '.tag_name' <<<"$release")"
    ref_type=tag
    release_url="$(jq -r '.html_url // empty' <<<"$release")"
    release_published="$(jq -r '.published_at // empty' <<<"$release")"
    release_id="$(jq -r '.id // empty' <<<"$release")"
  else
    tags="$(fetch_json "$API/repos/$repo/tags?per_page=1" 2>/dev/null || true)"
    source_ref="$(jq -r '.[0].name // empty' <<<"${tags:-[]}")"
    if [[ -n "$source_ref" ]]; then
      ref_type=tag
    else
      source_ref="$(jq -r '.default_branch' <<<"$repo_json")"
      ref_type=branch
    fi
    release_url=""; release_published=""; release_id=""
  fi

  clone_url="https://github.com/$repo.git"
  if [[ -d "$repo_dir/.git" ]]; then
    [[ -z "$(git -c core.longpaths=true -C "$repo_dir" status --porcelain)" ]] || die "lokale Änderungen im Clone verhindern Update: $repo_dir"
    if [[ "$ref_type" == tag ]]; then
      git -c core.longpaths=true -C "$repo_dir" fetch --depth="$DEPTH" --force origin "refs/tags/$source_ref:refs/tags/$source_ref"
      git -c core.longpaths=true -C "$repo_dir" checkout --detach "$source_ref"
    else
      git -c core.longpaths=true -C "$repo_dir" fetch --depth="$DEPTH" origin "$source_ref"
      git -c core.longpaths=true -C "$repo_dir" checkout --detach FETCH_HEAD
    fi
  else
    git clone -c core.longpaths=true --depth "$DEPTH" --single-branch --branch "$source_ref" "$clone_url" "$repo_dir"
  fi
  commit="$(git -C "$repo_dir" rev-parse HEAD)"

  assets_file="$dest/.assets.tmp"
  : > "$assets_file"
  checksums_name=""
  checksums_sha256=""

  if [[ -n "$release" ]]; then
    checksums_body="$(fetch_json "${API}/repos/$repo/releases/latest" 2>/dev/null || true)"
    checksums_url="$(asset_url "$checksums_body" '^SHA256SUMS\.txt$')"
    checksums_name="$(asset_name "$checksums_body" '^SHA256SUMS\.txt$')"
    if [[ -n "$checksums_url" ]]; then
      curl -fL --retry 3 "$checksums_url" -o "$dest/$checksums_name"
      checksums_sha256="$(sha256 "$dest/$checksums_name")"
    fi

    download_asset() {
      local platform="$1" regex="$2" portable="$3"
      local url name file hash expected sig_url sig_name verification=none
      url="$(asset_url "$release" "$regex")"
      name="$(asset_name "$release" "$regex")"
      if [[ -z "$url" && "$platform" == windows-x64 ]]; then
        url="$(asset_url "$release" 'x64-setup\.exe$|windows-x64.*\.exe$')"
        name="$(asset_name "$release" 'x64-setup\.exe$|windows-x64.*\.exe$')"
        portable=false
      fi
      if [[ -z "$url" ]]; then
        echo "WARN: kein Release-Asset für $platform ($repo)" >&2
        return 0
      fi
      file="$dest/$name"
      curl -fL --retry 3 "$url" -o "$file"
      hash="$(sha256 "$file")"
      if [[ -n "$checksums_name" ]]; then
        expected="$(awk -v n="$name" '$2==n || $2=="*"n {print $1; exit}' "$dest/$checksums_name")"
        if [[ -n "$expected" ]]; then
          [[ "${expected,,}" == "${hash,,}" ]] || die "SHA-256 stimmt nicht: $name"
          verification=checksums
        elif [[ "$platform" == macos ]]; then
          # macOS DMGs are not in SHA256SUMS.txt and have no .asc; they rely on
          # Apple code signing / notarization, which can only be checked on a Mac.
          echo "WARN: $name nicht in Prüfsummenliste; Herkunft nur per Apple-Codesignatur prüfbar ($repo)" >&2
          verification=apple-codesign-unchecked
        else
          die "Prüfsummenliste nennt $name nicht ($repo)"
        fi
      fi
      sig_url="$(asset_url "$release" "^${name//./\\.}\\.asc$")"
      sig_name="$(asset_name "$release" "^${name//./\\.}\\.asc$")"
      if [[ -n "$sig_url" ]]; then
        curl -fL --retry 3 "$sig_url" -o "$dest/$sig_name"
      fi
      if [[ "$VERIFY_SIGNATURES" == true && -n "$sig_url" ]]; then
        verify_signature "$dest/$sig_name" "$file"
        verification=gpg
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$platform" "$name" "$url" "$hash" "$portable" "$verification" "${sig_url:-}" >> "$assets_file"
    }

    [[ "$WANT_MACOS" == true ]] && download_asset macos 'universal.*\.dmg$|macos.*\.dmg$' false
    [[ "$WANT_WINDOWS_X64" == true ]] && download_asset windows-x64 'windows-x64-portable\.zip$' true
    [[ "$WANT_WINDOWS_ARM64" == true ]] && download_asset windows-arm64 'windows-arm64-portable\.zip$' true
    [[ "$WANT_WINDOWS_X86" == true ]] && download_asset windows-x86 'windows-x86-portable\.zip$' true

    for key in "${!ASSET_SELECTION[@]}"; do
      [[ "${ASSET_SELECTION[$key]}" == true ]] || continue
      case "$key" in
        linux-x86_64-deb) download_asset "$key" 'linux-x86_64\.deb$' false ;;
        linux-x86_64-appimage) download_asset "$key" 'linux-x86_64\.AppImage$' false ;;
        linux-x86_64-flatpak) download_asset "$key" 'linux-x86_64\.flatpak$' false ;;
        linux-x86_64-rpm) download_asset "$key" 'linux-x86_64\.rpm$' false ;;
        linux-x86_64-tar-gz) download_asset "$key" 'linux-x86_64\.tar\.gz$' false ;;
        linux-x86_64-pkg-tar-zst) download_asset "$key" 'linux-x86_64\.pkg\.tar\.zst$' false ;;
        linux-aarch64-deb) download_asset "$key" 'linux-aarch64\.deb$' false ;;
        linux-aarch64-appimage) download_asset "$key" 'linux-aarch64\.AppImage$' false ;;
        linux-aarch64-flatpak) download_asset "$key" 'linux-aarch64\.flatpak$' false ;;
        linux-aarch64-rpm) download_asset "$key" 'linux-aarch64\.rpm$' false ;;
        linux-aarch64-tar-gz) download_asset "$key" 'linux-aarch64\.tar\.gz$' false ;;
        linux-aarch64-pkg-tar-zst) download_asset "$key" 'linux-aarch64\.pkg\.tar\.zst$' false ;;
        linux-riscv64-deb) download_asset "$key" 'linux-riscv64\.deb$' false ;;
        linux-riscv64-rpm) download_asset "$key" 'linux-riscv64\.rpm$' false ;;
        linux-riscv64-tar-gz) download_asset "$key" 'linux-riscv64\.tar\.gz$' false ;;
      esac
    done

    if [[ "$VERIFY_SIGNATURES" == true ]]; then
      checksums_sig_url="$(asset_url "$release" '^SHA256SUMS\.txt\.asc$')"
      checksums_sig_name="$(asset_name "$release" '^SHA256SUMS\.txt\.asc$')"
      if [[ -n "$checksums_sig_url" && -n "$checksums_name" ]]; then
        curl -fL --retry 3 "$checksums_sig_url" -o "$dest/$checksums_sig_name"
        verify_signature "$dest/$checksums_sig_name" "$dest/$checksums_name"
      else
        echo "WARN: keine signierte SHA256SUMS.txt für $repo; GPG-Herkunft nicht bestätigt" >&2
      fi
    fi
  fi

  {
    printf 'schema_version = 1\n'
    printf 'name = %s\n' "$(q "$display")"
    printf 'slug = %s\n' "$(q "$slug")"
    printf 'group = %s\n' "$(q "$group")"
    printf 'category = %s\n' "$(q "$category")"
    printf 'repository = %s\n' "$(q "$repo")"
    printf 'repository_url = %s\n' "$(q "$clone_url")"
    printf 'source_ref = %s\n' "$(q "$source_ref")"
    printf 'source_ref_type = %s\n' "$(q "$ref_type")"
    printf 'commit = %s\n' "$(q "$commit")"
    printf 'clone_depth = %s\n' "$DEPTH"
    printf 'shallow = true\n'
    printf 'release_id = %s\n' "$(q "$release_id")"
    printf 'release_url = %s\n' "$(q "$release_url")"
    printf 'release_published_at = %s\n' "$(q "$release_published")"
    printf 'checksums_file = %s\n' "$(q "$checksums_name")"
    printf 'checksums_sha256 = %s\n' "$(q "$checksums_sha256")"
    printf 'signature_verification_requested = %s\n' "$VERIFY_SIGNATURES"
    printf 'archived_at = %s\n\n' "$(q "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")"
    while IFS=$'\t' read -r platform name url hash portable verification sig_url; do
      [[ -n "$platform" ]] || continue
      printf '[[assets]]\n'
      printf 'platform = %s\n' "$(q "$platform")"
      printf 'filename = %s\n' "$(q "$name")"
      printf 'url = %s\n' "$(q "$url")"
      printf 'sha256 = %s\n' "$(q "$hash")"
      printf 'portable = %s\n' "$portable"
      printf 'signature_url = %s\n' "$(q "$sig_url")"
      printf 'verification = %s\n\n' "$(q "$verification")"
    done < "$assets_file"
  } > "$dest/provenance.toml"

  rm -f "$assets_file"
done < "$MANIFEST"

if [[ -n "$TEMP_ROOT" ]]; then
  rm -rf -- "$TARGET_ROOT"
  mv -- "$TEMP_ROOT" "$TARGET_ROOT"
  ROOT="$TARGET_ROOT"
fi

echo "Fertig: $ROOT"
