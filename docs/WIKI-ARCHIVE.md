# Craft Wiki archive and local viewer

`mise run wiki:archive` shallow-clones `storytold/craft-wiki`, builds its Astro static site, cross-compiles the Go viewer for selected target systems, and writes provenance alongside the archived source and rendered output.

## Output

```text
craft-archive/documentation/craft-wiki/
├── source/             # shallow clone of storytold/craft-wiki
├── dist/               # Astro static output
├── launchers/          # viewer binaries, grouped by GOOS-GOARCH
├── start.cmd           # Windows: double-click to open the wiki
├── start.command       # macOS: double-click to open the wiki
├── start.sh            # Linux: run to open the wiki
├── provenance.toml     # source, build, output hashes, and viewer metadata
└── README.txt          # how to open the archive, for whoever receives it
```

The `craft-wiki/` folder is self-contained and relocatable: move or copy it anywhere (another disk, a USB stick, another machine) and it keeps working. Nothing records an absolute path, and the start scripts and the viewer resolve `dist/` from their own location.

The local copy is a static, read-only view. Cloudflare Worker routes for authentication and the CMS API are not available locally.

## Build

Install the tools declared in `mise.toml`, plus Git and Bash. `mise.toml` pins Node 22 (matching the wiki's `.nvmrc`) for the build, which installs from the repository's `package-lock.json`, and Go for the viewer. Cross-compiling the viewer requires no target OS SDK and uses `CGO_ENABLED=0`, so each binary is self-contained.

```sh
mise install
mise run wiki:build
mise run wiki:launcher:build
mise run wiki:archive
```

By default, the launcher task targets Windows amd64/arm64, macOS amd64/arm64, and Linux amd64/arm64. Choose a subset with `--targets`, for example:

```sh
mise run wiki:launcher:build -- --targets windows-amd64,darwin-arm64,linux-amd64
```

`mise run wiki:archive` accepts the same `--targets` option. The environment variable `CRAFT_WIKI_TARGETS` accepts the same comma-separated target names; `--targets` takes precedence. Supported targets are `windows-amd64`, `windows-arm64`, `darwin-amd64`, `darwin-arm64`, `linux-amd64`, and `linux-arm64`. Each build replaces `launchers/`, so it contains exactly the targets recorded in `provenance.toml`.

## Open the archived wiki

Use the start script for your system in the `craft-wiki/` folder: double-click `start.cmd` on Windows or `start.command` on macOS, or run `./start.sh` on Linux. Each one picks the viewer for the machine's architecture and passes extra arguments through, for example `./start.sh --port 0`.

The binaries can also be run directly, for example:

```sh
./craft-archive/documentation/craft-wiki/launchers/linux-amd64/craft-wiki-viewer
```

`mise run wiki:launch` prints the command for the current machine.

The viewer locates the `dist/` directory next to `launchers/` automatically, binds only to `127.0.0.1`, and opens the default browser. It defaults to port `42420`; if that port is occupied, use `--port 0` to let the OS allocate an available port. A fixed alternate port can be passed explicitly:

```sh
./craft-wiki-viewer --root ./dist --port 42421 --no-open
```

Supported options:

- `--root <directory>`: site root (normally inferred from the viewer's location)
- `--port <number>`: port from 0 through 65535; 0 chooses an available port, and the browser opens on the port actually used
- `--host`: loopback only (`127.0.0.1` or `localhost`); other values are rejected
- `--no-open`: do not launch the browser

## Provenance

`provenance.toml` records the checked-out ref and commit, shallow clone depth, Node version, npm lockfile hash, build timestamps (local time with UTC offset), deterministic rendered-tree hash, and each target binary's path (relative to the archive folder) and SHA-256. The viewer binary itself does not contain the static site; keep `dist/` next to `launchers/` when distributing the archive.

On macOS, Gatekeeper may block the unsigned viewer and start script after a download. Allow them under System Settings > Privacy & Security, or run `xattr -dr com.apple.quarantine .` in the `craft-wiki/` folder.
