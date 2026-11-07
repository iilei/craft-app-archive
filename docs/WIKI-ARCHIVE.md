# Craft Wiki archive and local viewer

`mise run wiki:archive` shallow-clones `storytold/craft-wiki`, builds its Astro static site, cross-compiles the Go viewer for selected target systems, and writes provenance alongside the archived source and rendered output.

## Output

```text
craft-archive/documentation/craft-wiki/
├── source/             # shallow clone of storytold/craft-wiki
├── dist/               # Astro static output
├── launchers/          # viewer binaries, grouped by GOOS-GOARCH
├── provenance.toml     # source, build, output hashes, and viewer metadata
└── README.txt
```

The local copy is a static, read-only view. Cloudflare Worker routes for authentication and the CMS API are not available locally.

## Build

Install the tools declared in `mise.toml`, plus Git and Bash. The wiki build uses the Node version selected by mise and the repository's `package-lock.json`; cross-compiling the viewer requires no target OS SDK and uses `CGO_ENABLED=0`.

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

The environment variable `CRAFT_WIKI_TARGETS` accepts the same comma-separated target names. Supported targets are `windows-amd64`, `windows-arm64`, `darwin-amd64`, `darwin-arm64`, `linux-amd64`, and `linux-arm64`.

## Open the archived wiki

Run the binary for the host OS/architecture. From the archive root, for example:

```sh
./craft-archive/documentation/craft-wiki/launchers/linux-amd64/craft-wiki-viewer
```

The viewer locates the sibling `dist/` directory automatically, binds only to `127.0.0.1`, and opens the default browser. It defaults to port `42420`; if that port is occupied, use `--port 0` to let the OS allocate an available port. A fixed alternate port can be passed explicitly:

```sh
./craft-wiki-viewer --root ./dist --port 42421 --no-open
```

Supported options:

- `--root <directory>`: site root (normally inferred from the viewer's location)
- `--port <number>`: port from 0 through 65535; 0 chooses an available port
- `--host`: loopback only (`127.0.0.1` or `localhost`); other values are rejected
- `--no-open`: do not launch the browser

## Provenance

`provenance.toml` records the checked-out ref and commit, shallow clone depth, Node version, npm lockfile hash, build timestamps, deterministic rendered-tree hash, and each target binary's path and SHA-256. The viewer binary itself does not contain the static site; keep the adjacent `dist/` directory when distributing the archive.
