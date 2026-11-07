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

Each app folder contains `source/` (shallow Git clone), the selected release files, optional checksum/signature files, and `provenance.toml` with the exact source commit, release metadata, asset URLs, and SHA-256 digests.

## Requirements

- `mise`
- Git and Bash; on Windows, run from Git Bash (mise itself may be installed on Windows)
- `curl`
- A GitHub API token is optional but recommended for reliable API rate limits: set `GH_TOKEN`.
- `gpg` is only required for optional signature verification.

`mise install` installs the pinned `jq` parser. Other commands are provided by the host shell. `mise` task `usage` flags are used to parse arguments (no separate CLI parser dependency).

## Run

```sh
mise install
mise run archive
```

Defaults: clone depth `20`; download the macOS universal DMG, Windows x64 package, and Linux x86_64 `.deb` for each latest stable GitHub release. The archive is saved to `craft-archive/` unless `CRAFT_ARCHIVE_DIR` is set.

```sh
# Change clone depth; defaults for platforms remain enabled.
mise run archive --depth 5

# Disable platform downloads individually. The corresponding source clone and provenance are still created.
mise run archive --no-macos
mise run archive --no-windows-x64 --no-linux-x86_64-deb

# Choose a custom destination and authenticate GitHub API requests.
CRAFT_ARCHIVE_DIR=/mnt/backup/craft GH_TOKEN="$GH_TOKEN" mise run archive
```

The platform booleans default to `true`, and `--no-<flag>` disables a platform. ArtCraft Studio currently has no Windows portable ZIP in its latest release; the task falls back to its x64 setup executable and records `portable = false`. macOS DMGs are installer images, not unpacked app bundles. Availability varies by release; missing platform assets are warned about and skipped.

## Signature verification

Release asset hashes are always computed locally. When the release publishes `SHA256SUMS.txt`, every downloaded installer is checked against it. This detects transfer errors but does **not** by itself authenticate the publisher, since the checksum file is hosted alongside the assets.

GPG verification is opt-in. It requires a release public key and fingerprint obtained and verified independently (do not trust a key merely because it was downloaded from the same GitHub release):

```sh
CRAFT_GPG_KEY_FILE=/secure/path/release-key.asc \
CRAFT_GPG_FINGERPRINT=0123456789ABCDEF0123456789ABCDEF01234567 \
mise run archive --verify-signatures
```

The fingerprint must match the imported key. If a signed `SHA256SUMS.txt.asc` exists, it is verified before relying on its hashes. Individual asset `.asc` signatures are also verified when provided. If a release does not provide a signed checksum list or signatures, the task warns; signature verification cannot be claimed for that release. A valid checksum without a trusted signature is integrity checking, not proof of origin.

## Reproducibility notes

A run selects each repository's latest stable GitHub release and uses that release's tag as the source ref. If no stable release exists, it falls back to the first GitHub tag; if no tags exist, it uses the repository's default branch. `provenance.toml` records the resulting commit SHA, exact tag/branch, requested depth, release ID/URL/date, and installer checksums. Thus future runs may select newer versions, while each completed archive records precisely what it captured.

GitHub API requests are made at runtime, so the set of latest releases is intentionally not pinned. Save the resulting provenance files alongside the downloads to preserve a record of each run.
