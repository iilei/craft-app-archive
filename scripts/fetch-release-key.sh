#!/usr/bin/env bash
set -euo pipefail

# Trust is anchored to this independently verified full fingerprint, not to
# the GitHub release URL or the short key ID.
readonly EXPECTED_FINGERPRINT="9F494AB282B2F20C80D16128EC2AAF6D2213BF17"
readonly KEY_URL="https://github.com/storytold/artcraft/releases/latest/download/release-signing-key.asc"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly OUTPUT="${CRAFT_GPG_KEY_OUTPUT:-$REPO_ROOT/keys/storytold-release-key.asc}"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || fail "curl is required to fetch the release key"
command -v gpg >/dev/null 2>&1 || fail "gpg is required to verify the release key"

mkdir -p "$(dirname "$OUTPUT")"
tmp_home="$(mktemp -d)"
tmp_key="${OUTPUT}.tmp.$$"
tmp_download="${tmp_home}/release-signing-key.asc"
trap 'rm -rf "$tmp_home"; rm -f "$tmp_key"' EXIT
chmod 700 "$tmp_home"

if ! curl --fail --location --silent --show-error --retry 3 \
  --proto '=https' --tlsv1.2 \
  "$KEY_URL" -o "$tmp_download"; then
  fail "could not download release signing key from $KEY_URL"
fi

[[ -s "$tmp_download" ]] || fail "downloaded release key is empty"
head -n 1 "$tmp_download" | grep -Fxq -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' \
  || fail "download does not contain an ASCII-armored OpenPGP public key"

if ! GNUPGHOME="$tmp_home" gpg --batch --quiet --import "$tmp_download"; then
  fail "downloaded file could not be imported as an OpenPGP public key"
fi

fingerprint="$(GNUPGHOME="$tmp_home" gpg --batch --with-colons --fingerprint \
  | awk -F: '$1 == "fpr" { print toupper($10); exit }')"
if [[ "$fingerprint" != "$EXPECTED_FINGERPRINT" ]]; then
  printf 'ERROR: downloaded key has unexpected fingerprint: %s\n' "${fingerprint:-<none>}" >&2
  printf 'Expected: %s\n' "$EXPECTED_FINGERPRINT" >&2
  exit 1
fi

GNUPGHOME="$tmp_home" gpg --batch --armor --export "$EXPECTED_FINGERPRINT" > "$tmp_key"
[[ -s "$tmp_key" ]] || fail "verified key export was empty"
mv "$tmp_key" "$OUTPUT"
printf 'Saved verified release key (%s) to %s\n' "$EXPECTED_FINGERPRINT" "$OUTPUT"
