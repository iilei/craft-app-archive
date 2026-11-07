#!/usr/bin/env bash
set -euo pipefail

# Short key IDs are only lookup hints. Trust is anchored to the pinned full
# fingerprint, which must be independently checked before changing this file.
readonly KEY_ID="EC2AAF6D2213BF17"
readonly EXPECTED_FINGERPRINT="9F494AB282B2F20C80D16128EC2AAF6D2213BF17"
readonly KEY_SERVER="hkps://keyserver.ubuntu.com"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly OUTPUT="${CRAFT_GPG_KEY_OUTPUT:-$REPO_ROOT/keys/storytold-release-key.asc}"

command -v gpg >/dev/null 2>&1 || { echo "ERROR: gpg is required to fetch/verify the release key" >&2; exit 1; }
mkdir -p "$(dirname "$OUTPUT")"
tmp_home="$(mktemp -d)"
tmp_key="${OUTPUT}.tmp.$$"
trap 'rm -rf "$tmp_home"; rm -f "$tmp_key"' EXIT
chmod 700 "$tmp_home"
GNUPGHOME="$tmp_home" gpg --batch --keyserver "$KEY_SERVER" --recv-keys "$KEY_ID"

fingerprint="$(GNUPGHOME="$tmp_home" gpg --batch --with-colons --fingerprint "$KEY_ID" | awk -F: '$1 == "fpr" { print toupper($10); exit }')"
if [[ "$fingerprint" != "$EXPECTED_FINGERPRINT" ]]; then
  echo "ERROR: keyserver returned unexpected fingerprint: $fingerprint" >&2
  echo "Expected: $EXPECTED_FINGERPRINT" >&2
  exit 1
fi

GNUPGHOME="$tmp_home" gpg --batch --armor --export "$EXPECTED_FINGERPRINT" > "$tmp_key"
[[ -s "$tmp_key" ]] || { echo "ERROR: key export was empty" >&2; exit 1; }
mv "$tmp_key" "$OUTPUT"
echo "Saved pinned release key ($EXPECTED_FINGERPRINT) to $OUTPUT"
