# craft-app-archive

Cross-platform `mise` task to shallow-clone Craft Apps, archive latest release installers, and record provenance.

## What it does

This repository contains a reproducible archive workflow for all apps listed in the Craft Wiki:

- shallow source clones
- latest GitHub release assets
- per-app `provenance.toml`
- optional GPG signature verification
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
- `gpg` (required only when signature verification is enabled)

## Quick start

```bash
mise install
mise run archive
```

This defaults to:

- clone depth: `20`
- macOS: enabled
- Windows x64: enabled
- Linux x86_64 .deb: enabled
- signature verification: enabled

## Opt out of verification

By default, release signatures are checked. To disable them:

```bash
NO_VERIFY_SIGNATURE=1 mise run archive
```

or:

```bash
mise run archive --no-verify-signatures
```

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

The release verification is tied to a pinned GPG fingerprint:

```bash
mise run keys:fetch
```

This fetches the public key for key ID `EC2AAF6D2213BF17`, verifies the full pinned fingerprint:

```text
9F494AB282B2F20C80D16128EC2AAF6D2213BF17
```

and writes the exported key to:

```text
keys/storytold-release-key.asc
```

Important: the short key ID is only a lookup hint. The trust anchor is the full fingerprint, which should be independently confirmed before treating it as trusted.

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
