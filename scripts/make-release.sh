#!/bin/bash
# Packages an OSCcourier release zip for GitHub: the exported .app, README,
# Help.pdf (doubling as the quickstart), and the example projects.
#
# Usage: ./scripts/make-release.sh v0.2.0
#
# Prerequisites (one-time, or whenever you cut a new build):
#   1. In Xcode: Product > Archive (Release configuration).
#   2. In the Organizer: Distribute App > Custom > Copy App.
#   3. Save the export anywhere under ~/Documents/MyCode/OSCcourier-release/
#      (Xcode names the folder "OSCcourier <date> <time>" by default — that's
#      fine, this script finds the most recently modified OSCcourier.app
#      under that directory automatically).
#
# The example projects (JSON + Max/MSP patches) are expected at:
#   ~/Documents/MyCode/exemples/example1_autofill/{autofill.maxpat, OSCcourier_autofill.json}
#   ~/Documents/MyCode/exemples/example2_baroque/{baroque.maxpat, OSCcourier_baroque.json}
# Edit EXAMPLES_DIR / the example folder names below if that ever changes.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <version, e.g. v0.2.0>" >&2
    exit 1
fi
VERSION="$1"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable via env vars for testing in a sandboxed shell where $HOME
# isn't the real Mac home (e.g. Cowork's device bridge); on a normal Mac
# Terminal the defaults below are what you want.
RELEASE_DIR="${OSCCOURIER_RELEASE_DIR:-$HOME/Documents/MyCode/OSCcourier-release}"
EXAMPLES_DIR="${OSCCOURIER_EXAMPLES_DIR:-$HOME/Documents/MyCode/exemples}"
STAGING="$RELEASE_DIR/staging-$VERSION"
ZIP_PATH="$RELEASE_DIR/OSCcourier-$VERSION.zip"

echo "=== locating the exported .app ==="
# ls -dt (newest first) rather than stat -f/-c, so this works the same on
# both a real Mac Terminal (BSD tools) and this sandbox's Linux bridge
# (GNU tools) when testing.
APP_SRC="$(find "$RELEASE_DIR" -maxdepth 3 -iname 'OSCcourier.app' -not -path '*/staging-*' -exec ls -dt {} + 2>/dev/null | head -1)"
if [ -z "$APP_SRC" ]; then
    echo "No OSCcourier.app found under $RELEASE_DIR — export one from Xcode first (see script header)." >&2
    exit 1
fi
echo "Using: $APP_SRC"

echo "=== sanity checks ==="
for f in "$REPO_DIR/README.md" "$REPO_DIR/OSCcourier/Help.pdf" \
         "$EXAMPLES_DIR/example1_autofill/autofill.maxpat" \
         "$EXAMPLES_DIR/example1_autofill/OSCcourier_autofill.json" \
         "$EXAMPLES_DIR/example2_baroque/baroque.maxpat" \
         "$EXAMPLES_DIR/example2_baroque/OSCcourier_baroque.json"; do
    [ -f "$f" ] || { echo "MISSING: $f" >&2; exit 1; }
done

echo "=== staging ==="
rm -rf "$STAGING"
PKG="$STAGING/OSCcourier-$VERSION"
mkdir -p "$PKG/examples/example1_autofill" "$PKG/examples/example2_baroque"

cp -R "$APP_SRC" "$PKG/OSCcourier.app"
cp "$REPO_DIR/README.md" "$PKG/README.md"
cp "$REPO_DIR/OSCcourier/Help.pdf" "$PKG/Help.pdf"
cp "$EXAMPLES_DIR/example1_autofill/autofill.maxpat" "$PKG/examples/example1_autofill/"
cp "$EXAMPLES_DIR/example1_autofill/OSCcourier_autofill.json" "$PKG/examples/example1_autofill/"
cp "$EXAMPLES_DIR/example2_baroque/baroque.maxpat" "$PKG/examples/example2_baroque/"
cp "$EXAMPLES_DIR/example2_baroque/OSCcourier_baroque.json" "$PKG/examples/example2_baroque/"

echo "=== zipping ==="
# Remove any previous zip for this version first: zip -r into an existing
# archive UPDATES it in place rather than replacing it, which would leave
# stale entries around from an earlier run instead of a clean rebuild.
rm -f "$ZIP_PATH"
(cd "$STAGING" && zip -r -y -q "$ZIP_PATH" "OSCcourier-$VERSION")

echo "=== done ==="
ls -la "$ZIP_PATH"
echo "Ready to attach to a GitHub Release."
