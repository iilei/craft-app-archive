#!/usr/bin/env bash
set -euo pipefail

ROOT="${CRAFT_ARCHIVE_DIR:-craft-archive}"
MANIFEST="${CRAFT_APPS_MANIFEST:-apps.tsv}"
API="https://api.github.com"
DEPTH=20
WANT_MACOS=true
WANT_WINDOWS=true
WANT_LINUX=true
VERIFY_SIGNATURES=false
AUTH=()
[[ -n "${GH_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer $GH_TOKEN")

usage() {
  cat >&2 <<'EOF'
Usage: archive-craft-apps.sh [--depth N] [--macos true|false]
       [--windows-x64 true|false] [--linux-x86_64-deb true|false]
       [--verify-signatures true|false]
Environment: CRAFT_ARCHIVE_DIR, CRAFT_APPS_MANIFEST, GH_TOKEN,
             CRAFT_GPG_KEY_FILE, CRAFT_GPG_FINGERPRINT
EOF
}
die() { echo "ERROR: $*" >&2; exit 1; }
q() { printf '%s' "$1" | jq -Rs .; }
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else die "sha256sum oder shasum ist erforderlich"
  fi
}
asset_url() {
  jq -r --arg re "$1" '[.assets[] | select(.name | test($re; "i"))][0].browser_download_url // empty' <<<"$release"
}
asset_name() {
  jq -r --arg re "$1" '[.assets[] | select(.name | test($re; "i"))][0].name // empty' <<<"$release"
}
fetch_json() {
  curl -fsSL --retry 3 "${AUTH[@]}" -H 'Accept: application/vnd.github+json' "$1"
}

while (($#)); do
  case "$1" in
    --depth) DEPTH="${2:?--depth requires a value}"; shift 2 ;;
    --macos) WANT_MACOS="${2:?--macos requires true or false}"; shift 2 ;;
    --windows-x64) WANT_WINDOWS="${2:?--windows-x64 requires true or false}"; shift 2 ;;
    --linux-x86_64-deb) WANT_LINUX="${2:?--linux-x86_64-deb requires true or false}"; shift 2 ;;
    --verify-signatures) VERIFY_SIGNATURES="${2:?--verify-signatures requires true or false}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unrecognized argument: $1" ;;
  esac
done
[[ "$DEPTH" =~ ^[1-9][0-9]*$ ]] || die "depth muss eine positive ganze Zahl sein: $DEPTH"
for value in "$WANT_MACOS" "$WANT_WINDOWS" "$WANT_LINUX" "$VERIFY_SIGNATURES"; do
  [[ "$value" == true || "$value" == false ]] || die "boolean-Optionen müssen true oder false sein"
done
command -v git >/dev/null || die "git wird benötigt"
command -v curl >/dev/null || die "curl wird benötigt"
command -v jq >/dev/null || die "jq wird benötigt (mise install)"
[[ -f "$MANIFEST" ]] || die "Manifest fehlt: $MANIFEST"

GNUPGHOME_TMP=""
if [[ "$VERIFY_SIGNATURES" == true ]]; then
  command -v gpg >/dev/null || die "gpg wird für Signaturprüfung benötigt"
  [[ -f "${CRAFT_GPG_KEY_FILE:-}" ]] || die "setze CRAFT_GPG_KEY_FILE auf einen unabhängig beschafften, vertrauenswürdigen Release-Key"
  [[ -n "${CRAFT_GPG_FINGERPRINT:-}" ]] || die "setze CRAFT_GPG_FINGERPRINT auf den unabhängig verifizierten Fingerprint"
  GNUPGHOME_TMP="$(mktemp -d)"
  chmod 700 "$GNUPGHOME_TMP"
  export GNUPGHOME="$GNUPGHOME_TMP"
  trap 'rm -rf "$GNUPGHOME_TMP"' EXIT
  gpg --batch --quiet --import "$CRAFT_GPG_KEY_FILE"
  expected_fpr="$(printf '%s' "$CRAFT_GPG_FINGERPRINT" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
  imported_fpr="$(gpg --batch --with-colons --fingerprint | awk -F: '$1=="fpr" {print toupper($10); exit}')"
  [[ "$imported_fpr" == "$expected_fpr" ]] || die "der importierte GPG-Key-Fingerprint stimmt nicht mit CRAFT_GPG_FINGERPRINT überein"
fi

mkdir -p "$ROOT"
while IFS=$'\t' read -r group category slug display repo; do
  [[ -z "${repo:-}" || "$group" == \#* ]] && continue
  # Be tolerant of accidental whitespace in hand-edited manifests.
  category="${category# }"; category="${category% }"
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
    [[ -z "$(git -C "$repo_dir" status --porcelain)" ]] || die "lokale Änderungen im Clone verhindern Update: $repo_dir"
    if [[ "$ref_type" == tag ]]; then
      git -C "$repo_dir" fetch --depth="$DEPTH" --force origin "refs/tags/$source_ref:refs/tags/$source_ref"
      git -C "$repo_dir" checkout --detach "$source_ref"
    else
      git -C "$repo_dir" fetch --depth="$DEPTH" origin "$source_ref"
      git -C "$repo_dir" checkout --detach FETCH_HEAD
    fi
  elif [[ "$ref_type" == tag ]]; then
    git clone --depth "$DEPTH" --single-branch --branch "$source_ref" "$clone_url" "$repo_dir"
  else
    git clone --depth "$DEPTH" --single-branch --branch "$source_ref" "$clone_url" "$repo_dir"
  fi
  commit="$(git -C "$repo_dir" rev-parse HEAD)"

  assets_file="$dest/.assets.tmp"
  : > "$assets_file"
  checksums_name=""
  checksums_url=""
  checksums_sha256=""
  if [[ -n "$release" ]]; then
    checksums_url="$(asset_url '^SHA256SUMS\.txt$')"
    checksums_name="$(asset_name '^SHA256SUMS\.txt$')"
    if [[ -n "$checksums_url" ]]; then
      curl -fL --retry 3 "$checksums_url" -o "$dest/$checksums_name"
      checksums_sha256="$(sha256 "$dest/$checksums_name")"
    fi

    download_asset() {
      local platform="$1" regex="$2" portable="$3" url name file hash expected sig_url sig_name
      url="$(asset_url "$regex")"
      name="$(asset_name "$regex")"
      if [[ -z "$url" && "$platform" == windows-x64 ]]; then
        # ArtCraft currently publishes an x64 setup executable rather than a portable ZIP.
        url="$(asset_url 'x64-setup\.exe$|windows-x64.*\.exe$')"
        name="$(asset_name 'x64-setup\.exe$|windows-x64.*\.exe$')"
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
        [[ -n "$expected" ]] || die "Prüfsummenliste nennt $name nicht ($repo)"
        [[ "${expected,,}" == "${hash,,}" ]] || die "SHA-256 stimmt nicht: $name"
      fi
      sig_url="$(asset_url "^${name//./\\.}\\.asc$")"
      sig_name="$(asset_name "^${name//./\\.}\\.asc$")"
      if [[ -n "$sig_url" ]]; then
        curl -fL --retry 3 "$sig_url" -o "$dest/$sig_name"
      fi
      if [[ "$VERIFY_SIGNATURES" == true && -n "$sig_url" ]]; then
        verify_signature "$dest/$sig_name" "$file"
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$platform" "$name" "$url" "$hash" "$portable" "${sig_url:-}" >> "$assets_file"
    }

    verify_signature() {
      local signature="$1" data="$2" status
      status="$(gpg --batch --status-fd 1 --verify "$signature" "$data" 2>/dev/null || true)"
      grep -q "^\[GNUPG:\] VALIDSIG $expected_fpr " <<<"$status" || die "GPG-Signatur ungültig oder nicht vom gepinnten Schlüssel: $data"
    }

    [[ "$WANT_MACOS" == true ]] && download_asset macos 'universal.*\.dmg$|macos.*\.dmg$' false
    [[ "$WANT_WINDOWS" == true ]] && download_asset windows-x64 'windows-x64-portable\.zip$' true
    [[ "$WANT_LINUX" == true ]] && download_asset linux-x86_64-deb 'linux-x86_64\.deb$' false

    if [[ "$VERIFY_SIGNATURES" == true ]]; then
      checksums_sig_url="$(asset_url '^SHA256SUMS\.txt\.asc$')"
      checksums_sig_name="$(asset_name '^SHA256SUMS\.txt\.asc$')"
      if [[ -n "$checksums_url" && -n "$checksums_sig_url" ]]; then
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
    while IFS=$'\t' read -r platform name url hash portable sig_url; do
      [[ -n "$platform" ]] || continue
      printf '[[assets]]\n'
      printf 'platform = %s\n' "$(q "$platform")"
      printf 'filename = %s\n' "$(q "$name")"
      printf 'url = %s\n' "$(q "$url")"
      printf 'sha256 = %s\n' "$(q "$hash")"
      printf 'portable = %s\n' "$portable"
      printf 'signature_url = %s\n\n' "$(q "$sig_url")"
    done < "$assets_file"
  } > "$dest/provenance.toml"
  rm -f "$assets_file"
done < "$MANIFEST"
echo "Fertig: $ROOT"
