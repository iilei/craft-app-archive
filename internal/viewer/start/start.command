#!/bin/sh
# Start the Craft Wiki viewer on macOS (double-click in Finder opens Terminal).
# Paths are resolved from this script's location, so the archive folder can be
# moved or copied anywhere.
dir=$(cd "$(dirname "$0")" && pwd) || exit 1
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  arm64) arch=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
viewer="$dir/launchers/darwin-$arch/craft-wiki-viewer"
if [ ! -f "$viewer" ]; then
  echo "No viewer for darwin-$arch in this archive: $viewer" >&2
  exit 1
fi
exec "$viewer" --root "$dir/documentation" "$@"
