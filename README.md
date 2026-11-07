# craft-app-archive

Cross-platform `mise` task to shallow-clone Craft Apps, archive latest release installers, and record provenance.

## What it does

This repository contains a reproducible archive workflow for all apps listed in the Craft Wiki:

- shallow source clones
- latest GitHub release assets
- per-app `provenance.toml`
- GPG signature verification by default (with explicit opt-outs)
- output grouped by `OFFICIAL APPS` / `THIRD-PARTY APPS`

The archive layout is:

```text
craft-archive/
├── official-apps/
│   ├── ai-and-generative-media/
│   │   └── artcraft-studio/
│   │       ├── source/
│   │       ├── provenance.toml
│   │       └── release assets...
│   └── ...
└── third-party-apps/
    └── solidcraft/
        ├── source/
        ├── provenance.toml
        └── release assets...
```

## Requirements

- `mise`
- `git`
- `bash`
- `curl`
- `jq`
- `gpg` (required by the default signature verification)

## Quick start

From the repository directory:

```bash
mise install
mise run archive
```

This defaults to:

- clone depth: `20`
- destination: `craft-archive` under the repository directory
- macOS: enabled
- Windows x64: enabled
- Linux x86_64 .deb: enabled
- signature verification: enabled

## Choose where the archive is written

The `archive` task accepts `--destination` and `--overwrite`. The destination is the archive root; the script creates the app/category directories below it. Without `--overwrite`, the task refuses to use an existing destination directory. With `--overwrite`, it replaces that directory, so double-check the path before running.

You can run the task while your shell is in a different directory by using mise's global `-C` / `--cd` flag. `-C` points to the directory containing this repository's `mise.toml`; `--destination` is interpreted relative to the shell's current directory when it is relative. Use an absolute destination to make the location unambiguous.

For example, if the shell is currently in your home directory, the repository is `~/code/craft-app-archive`, and you want the archive at `~/Downloads/craft-app-archive`:

```bash
cd ~
mise -C ~/code/craft-app-archive run archive \
  --destination ~/Downloads/craft-app-archive \
  --overwrite
```

The equivalent explicit form of the global flag is:

```bash
mise --cd ~/code/craft-app-archive run archive \
  --destination ~/Downloads/craft-app-archive \
  --overwrite
```

`-C` / `--cd` tells mise to load and run the task as if started in the repository directory. It does not choose the archive output location; `--destination` does that.

## Opt out of verification

By default, release signatures are checked. To disable them:

```bash
NO_VERIFY_SIGNATURE=1 mise run archive
```

or:

```bash
mise run archive --no-verify-signatures
```

When verification is disabled, the archive task skips fetching the GPG key and does not check detached signatures. SHA-256 hashes are still calculated, and downloaded files are compared with the published checksum list when available.

## Additional architecture and package formats

The task supports extra Linux formats and architecture targets as opt-in flags:

### Linux x86_64

```bash
mise run archive \
  --linux-x86_64-appimage \
  --linux-x86_64-flatpak \
  --linux-x86_64-rpm \
  --linux-x86_64-tar-gz \
  --linux-x86_64-pkg-tar-zst
```

### Linux ARM64 / aarch64

```bash
mise run archive \
  --linux-aarch64-deb \
  --linux-aarch64-appimage \
  --linux-aarch64-flatpak \
  --linux-aarch64-rpm \
  --linux-aarch64-tar-gz \
  --linux-aarch64-pkg-tar-zst
```

### Linux RISC-V 64

```bash
mise run archive \
  --linux-riscv64-deb \
  --linux-riscv64-rpm \
  --linux-riscv64-tar-gz
```

### Windows extra architectures

```bash
mise run archive --windows-arm64 --windows-x86
```

## Key fetch / verification

The release verification is pinned to the ArtCraft Linux repository signing public key. The current pinned fingerprint is:

```text
2B76741B414AAD6CD33E631213A005C0B9D7C3ED
```

To fetch and verify the key independently from the official ArtCraft release asset:

```bash
mise run keys:fetch
```

This fetches the current release key from the official ArtCraft GitHub release asset and verifies that its fingerprint matches the pinned value above.

The exported key is written to:

```text
keys/storytold-release-key.asc
```

The full fingerprint is the trust anchor. The short key ID is only a lookup hint and should not be treated as trusted in isolation.

The key change is aligned with the ArtCraft Linux repository signing rollout documented in [storytold/artcraft-services#343](https://github.com/storytold/artcraft-services/pull/343).

## Provenance format

Each release directory contains a `provenance.toml` file with machine-readable metadata, for example:

```toml
schema_version = 1
name = "ArtCraft Studio"
slug = "artcraft-studio"
group = "official-apps"
category = "ai-and-generative-media"
repository = "storytold/artcraft"
repository_url = "https://github.com/storytold/artcraft.git"
source_ref = "artcraft-v0.41.1"
source_ref_type = "tag"
commit = "..."
clone_depth = 20
shallow = true
release_id = "..."
release_url = "https://github.com/storytold/artcraft/releases/tag/..."
release_published_at = "..."
checksums_file = "SHA256SUMS.txt"
checksums_sha256 = "..."
signature_verification_requested = true

[[assets]]
platform = "macos"
filename = "..."
url = "..."
sha256 = "..."
portable = false
signature_url = "..."
```

## Reproducibility

The workflow is intentionally data-driven:

- repo list is in `apps.tsv`
- release selection is runtime-based
- exact commit and tag are persisted in `provenance.toml`
- release assets and checksums are stored next to the clone

This makes each archive run auditable and reproducible, while still tracking the latest upstream release at run time.
