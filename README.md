# Craft App Archive

A cross-platform `mise` task that archives the projects listed by [Craft Wiki](https://github.com/storytold/craft-wiki): shallow source clones, latest GitHub release installers, and per-project `provenance.toml` files.

## Included apps and output layout

The manifest `apps.tsv` follows the wiki's app hierarchy. Category and project names are normalized to lowercase slugs; group folders are `official-apps` and `third-party-apps`.

```text
craft-archive/
├── official-apps/
│   ├── ai-and-generative-media/artcraft-studio/
│   ├── graphics-and-design/photocraft/
│   └── ...
└── third-party-apps/solidcraft/
```

Each app folder contains `source/` (shallow Git clone), selected release files, optional checksum/signature files, and `provenance.toml` with the source commit, release metadata, asset URLs, and SHA-256 digests.

## Requirements

- `mise`
- Git and Bash; on Windows, run from Git Bash
- `curl`, `gpg`, and a reachable HKPS keyserver for the default signature verification
- A GitHub API token is optional but recommended for API rate limits: set `GH_TOKEN`

`mise install` installs pinned `jq`. `mise run keys:fetch` retrieves the signing key into an isolated temporary GPG home, checks the pinned full fingerprint, and writes the verified public key to `keys/storytold-release-key.asc`.

## Run

```sh
mise install
mise run archive
```

Defaults: clone depth `20`; macOS universal DMG, Windows x64 package, and Linux x86_64 `.deb`; signature verification is **enabled**. Before archiving, the task runs `scripts/fetch-release-key.sh`, which fetches key ID `EC2AAF6D2213BF17` from `hkps://keyserver.ubuntu.com` and requires full fingerprint `9F494AB282B2F20C80D16128EC2AAF6D2213BF17`. The archive is saved to `craft-archive/` unless `CRAFT_ARCHIVE_DIR` is set.

```sh
# More Linux formats/architectures are opt-in.
mise run archive --linux-x86_64-appimage --linux-x86_64-rpm --linux-aarch64-deb

# Disable verification for a repository/release that has no signatures, or to run offline.
mise run archive --no-verify-signatures

# Fetch/check key separately.
mise run keys:fetch
```

### Linux package-format and architecture options

| Architecture | Available format flags |
|---|---|
| x86_64 | `--linux-x86_64-deb`, `--linux-x86_64-appimage`, `--linux-x86_64-flatpak`, `--linux-x86_64-rpm`, `--linux-x86_64-tar-gz`, `--linux-x86_64-pkg-tar-zst` |
| aarch64 / ARM64 | `--linux-aarch64-deb`, `--linux-aarch64-appimage`, `--linux-aarch64-flatpak`, `--linux-aarch64-rpm`, `--linux-aarch64-tar-gz`, `--linux-aarch64-pkg-tar-zst` |
| riscv64 | `--linux-riscv64-deb`, `--linux-riscv64-rpm`, `--linux-riscv64-tar-gz` |

Windows x64 remains enabled by default; `--windows-arm64` and `--windows-x86` are opt-in. The macOS DMG is universal. ArtCraft Studio may publish a setup executable instead of a Windows portable ZIP; the fallback is recorded as non-portable. Requested assets missing from a release are warned about and skipped.

## Signature verification and trust

The key-fetch script does **not** trust a key merely because it came from a keyserver: it retrieves by short ID only as a lookup, then requires the exact pinned full fingerprint before exporting the key. The fingerprint must be confirmed from an independent official source before relying on this pin; do not change it based solely on a keyserver result.

The archive task always computes local SHA-256 hashes and compares downloaded files with `SHA256SUMS.txt` when present. With verification enabled, it verifies available detached asset signatures and the signed checksum list using the pinned key. Some project releases may lack signatures; those cases are warned about rather than represented as verified. SHA-256 matching alone is integrity checking, not proof of publisher origin.

For key verification alone, use `mise run keys:fetch`. To change where the key is written, set `CRAFT_GPG_KEY_OUTPUT`. To disable signature checks for a run, pass `--no-verify-signatures`.

## Reproducibility notes

A run selects each repository's latest stable GitHub release and uses that release's tag as the source ref. If no stable release exists, it falls back to the first GitHub tag; if no tags exist, it uses the repository's default branch. Each `provenance.toml` records the selected commit, exact tag/branch, requested clone depth, release ID/URL/date, and installer checksums. Future runs may select newer versions; provenance captures what each run archived.
