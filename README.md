# craft-app-archive

Cross-platform `mise` task to shallow-clone Craft Apps, archive latest release installers, and record provenance.

## What it does

This repository contains a reproducible archive workflow for the apps listed in the Craft Wiki that publish Windows portable packages (ArtCraft Studio is excluded because it ships only installers):

- shallow source clones
- latest GitHub release assets
- per-app `provenance.toml`
- GPG signature verification by default (with explicit opt-outs)
- output grouped by `OFFICIAL APPS` / `THIRD-PARTY APPS`

The archive layout is:

```text
craft-archive/
├── apps.txt              # copy of the app list this archive was built from
├── UPDATE.txt            # how to refresh this archive, also for someone it was handed to
├── official-apps/
│   ├── graphics-and-design/
│   │   └── photocraft/
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

Turn off a default target with `--no-macos`, `--no-windows-x64` or `--no-linux-x86_64-deb`.

## Choose where the archive is written

The `archive` task accepts `--destination` and `--overwrite`. The destination is the archive root; the script creates the app/category directories below it. Without `--overwrite`, the task refuses to use an existing destination directory. With `--overwrite`, it replaces that directory, so double-check the path before running.

You can run the task while your shell is in a different directory by using mise's global `-C` / `--cd` flag. `-C` points to the directory containing this repository's `mise.toml`. mise runs the task in that directory, so a relative `--destination` is resolved from the repository directory, not from the shell's current directory. Use an absolute destination for any location outside the repository.

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

`-C` / `--cd` tells mise to load and run the task as if started in the repository directory. It does not choose the archive output location; `--destination` does that. Use an absolute destination whenever you want to archive to a location outside the repo.

## Interrupted runs, retries and GitHub rate limits

Failed network requests (GitHub API calls, downloads, git clone/fetch) are retried before a run gives up: 3 retries by default, waiting 5 s, 10 s and then 15 s. Tune this with `--retries` and `--retry-delay` (the first wait, in seconds; each further retry waits one more step):

```bash
mise run archive --retries 5 --retry-delay 10
```

If a run still fails, its progress is kept in a staging directory next to the destination (`.craft-archive.stage` for the default destination), and the task tells you so. Run the same command again with `--resume` to continue: apps that were finished are skipped, and an app that was interrupted is started over.

```bash
mise run archive --resume
```

Without `--resume`, the task refuses to start while an unfinished run exists, so no progress is discarded by accident; remove the staging directory to start over. A resumed run must use the same options and app list as the run it continues (retry settings may differ). A lock directory (`.craft-archive.lock`) prevents two runs on the same destination at once.

Without a token, the GitHub API allows only 60 requests per hour, and each app needs about three, so a full run plus a retry within the same hour can use them all up. When that happens, the run stops right away and prints when the limit resets; a short retry cannot help. Set `GH_TOKEN` to any GitHub token (no scopes needed) to raise the limit to 5000 requests per hour:

```bash
GH_TOKEN=$(gh auth token) mise run archive --resume
```

## Windows: long file paths

Windows limits a full path to 260 characters (`MAX_PATH`) by default; Linux and macOS allow far longer paths. This has nothing to do with `\` versus `/` separators. Each clone lives several levels deep, and during a run the archive is built in a temporary stage directory next to the destination, for example:

```text
C:\Users\<you>\code\craft-app-archive\.craft-archive.stage\official-apps\graphics-and-design\photocraft\source\
```

Files nested inside a repository can push the total past 260 characters, and Git for Windows then fails with `Filename too long`.

The scripts pass `-c core.longpaths=true` to `git clone`, `fetch`, `checkout` and `status`, so Git itself handles long paths without changes to your global Git config. Other Windows programs (Explorer, archivers, some editors) may still struggle with the archived files unless long paths are enabled system-wide. On Windows 10 1607 or later, run this in an elevated PowerShell, then sign out and back in:

```powershell
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
  -Name LongPathsEnabled -Value 1 -PropertyType DWORD -Force
```

If you cannot change that setting, a short destination close to the drive root keeps paths well below the limit:

```bash
mise run archive --destination C:/ca
```

## Edit the app list

`apps.txt` is a fixed-width table: columns are separated by at least two spaces, so a single space can appear inside a value (`Craft Anything`), and `-` marks an empty cell (third-party apps have no category). Values must not contain two consecutive spaces.

Add or change rows without worrying about alignment (tabs or any run of 2+ spaces work as separators), then realign the file:

```bash
mise run apps:fmt
```

`mise run apps:check` fails with a diff when the file is not formatted, which makes it suitable for CI. Both tasks reject rows with the wrong number of columns.

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

Windows downloads are portable `.zip` packages only. If a release has no portable package for a selected architecture, that download is skipped with a warning; installers are not used as a fallback. Apps that publish no Windows portable package at all are not listed in `apps.txt`.

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
name = "PhotoCraft"
slug = "photocraft"
group = "official-apps"
category = "graphics-and-design"
repository = "storytold/photocraft"
repository_url = "https://github.com/storytold/photocraft.git"
source_ref = "v0.21.0"
source_ref_type = "tag"
commit = "..."
clone_depth = 20
shallow = true
release_id = "..."
release_url = "https://github.com/storytold/photocraft/releases/tag/..."
release_published_at = "..."
checksums_file = "SHA256SUMS.txt"
checksums_sha256 = "..."
signature_verification_requested = true

[[assets]]
platform = "linux-x86_64-deb"
filename = "..."
url = "..."
sha256 = "..."
portable = false
signature_url = "..."
verification = "gpg"
```

Each asset's `verification` records the strongest check the archive run performed on it:

| Value | Meaning |
|---|---|
| `gpg` | Detached `.asc` signature verified against the pinned release key. |
| `checksums` | SHA-256 matched the release's `SHA256SUMS.txt`. That list is itself GPG-verified when a `SHA256SUMS.txt.asc` exists; otherwise the run warns that GPG provenance is not confirmed. |
| `apple-codesign-unchecked` | macOS DMG that is neither in `SHA256SUMS.txt` nor GPG-signed. Its authenticity rests on Apple code signing and notarization, which the archive run cannot check. Verify it on a Mac, for example with `spctl -a -vv -t install` on the mounted app, before relying on it. |
| `none` | The release has no `SHA256SUMS.txt` and no signature was verified (none published, or verification disabled). Only the recorded `sha256` is available to detect later changes. |

## Reproducibility

The workflow is intentionally data-driven:

- repo list is in `apps.txt`, and a copy is stored at the archive root when a run completes
- `UPDATE.txt` at the archive root holds the exact `mise run archive` command (with this run's options) that refreshes it, the tooling commit used, and, for anyone the archive is handed to, where to get this repository and mise
- release selection is runtime-based
- exact commit and tag are persisted in `provenance.toml`
- release assets and checksums are stored next to the clone

This makes each archive run auditable and reproducible, while still tracking the latest upstream release at run time.
