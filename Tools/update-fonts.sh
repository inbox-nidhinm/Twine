#!/bin/bash
# Copies the files Twine ships of its display face, AA Bridge Slab, from the
# AA-Bridge repo (the submodule at Vendor/AA-Bridge) into the places Twine
# reads them from:
#
#     the variable font  Packages/MotionKit/Sources/Theme/Resources/Fonts/AABridgeSlab.ttf
#     its licence        Packages/MotionKit/Sources/Theme/Resources/Fonts/AABridgeSlab-OFL.txt
#     the web font       FigmaPlugin/AABridgeSlab.woff2 (embedded in the plugin's panel)
#
# Those copies are committed, so anyone can build Twine without the
# submodule (AA-Bridge is private). When the submodule is not checked out,
# this does nothing and the committed copies are used.
#
# make-app.sh runs this on every build. Only files that differ are copied,
# and when the web font changes the plugin's panel is rebuilt.
set -euo pipefail
cd "$(dirname "$0")/.."

SLAB=Vendor/AA-Bridge/slab
[[ -f "$SLAB/OFL.txt" ]] || exit 0

FONTS=Packages/MotionKit/Sources/Theme/Resources/Fonts
WOFF2=FigmaPlugin/AABridgeSlab.woff2
copy() {
    if ! cmp -s "$1" "$2"; then
        cp "$1" "$2"
        echo "updated $2 from the AA-Bridge submodule"
    fi
}

copy "$SLAB/fonts/variable/AABridgeSlab[opsz,wght].ttf" "$FONTS/AABridgeSlab.ttf"
copy "$SLAB/OFL.txt" "$FONTS/AABridgeSlab-OFL.txt"
before=$(shasum "$WOFF2" 2>/dev/null || true)
copy "$SLAB/fonts/webfonts/AABridgeSlab[opsz,wght].woff2" "$WOFF2"
if [[ "$(shasum "$WOFF2")" != "$before" ]]; then
    TWINE_FONTS_COPIED=1 python3 FigmaPlugin/build.py
fi
