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

`mise install` installs the pinned `jq` parser. Other commands are provided by the host shell. `mise` task `usage` flags parse task arguments.

## Run

```sh
mise install
mise run archive
```

Defaults are unchanged: clone depth `20`; download the macOS universal DMG, Windows x64 portable package, and Linux x86_64 `.deb` for each latest stable GitHub release. All additional package formats and architectures are opt-in. The archive is saved to `craft-archive/` unless `CRAFT_ARCHIVE_DIR` is set.

### Linux package-format and architecture options

Linux formats can be selected independently by architecture. Each option defaults to `false` except the existing `--linux-x86_64-deb`, which remains `true`:

| Architecture | Available format flags |
|---|---|
| x86_64 | `--linux-x86_64-deb`, `--linux-x86_64-appimage`, `--linux-x86_64-flatpak`, `--linux-x86_64-rpm`, `--linux-x86_64-tar-gz`, `--linux-x86_64-pkg-tar-zst` |
| aarch64 / ARM64 | `--linux-aarch64-deb`, `--linux-aarch64-appimage`, `--linux-aarch64-flatpak`, `--linux-aarch64-rpm`, `--linux-aarch64-tar-gz`, `--linux-aarch64-pkg-tar-zst` |
| riscv64 | `--linux-riscv64-deb`, `--linux-riscv64-rpm`, `--linux-riscv64-tar-gz` |

Select multiple formats and architectures in one run. For example:

```sh
mise run archive --linux-x86_64-appimage --linux-x86_64-rpm --linux-aarch64-deb
```

Use the negated form to switch off an enabled default, for example `--no-linux-x86_64-deb`. Release assets are checked per repository; an unavailable requested format is warned about and skipped.

### Other architecture options

Windows x64 remains enabled by default. Windows ARM64 and x86 can be added explicitly:

```sh
mise run archive --windows-arm64 --windows-x86
```

The macOS DMG is published as universal by these projects; there are no separate Intel/Apple-Silicon asset flags. ArtCraft Studio currently has no Windows portable ZIP in its latest release; the task falls back to its x64 setup executable and records `portable = false`.

Change clone depth without changing asset defaults:

```sh
mise run archive --depth 5
```

Choose a custom destination and authenticate GitHub API requests:

```sh
CRAFT_ARCHIVE_DIR=/mnt/backup/craft GH_TOKEN="$GH_TOKEN" mise run archive
```

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
