#!/usr/bin/env bash
#
# build-plasmoid.sh - packages plasmoid/ into gpu-boost-toggle.plasmoid,
# a zip file Plasma's widget installer understands.
#
# Once built, install/update it without root and without install.sh via
# either:
#   kpackagetool6 -t Plasma/Applet -i gpu-boost-toggle.plasmoid   (first install)
#   kpackagetool6 -t Plasma/Applet -u gpu-boost-toggle.plasmoid   (upgrade)
# or by dragging the file into Plasma's Add Widgets > Get New... >
# Install Widget From Local File... dialog.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLASMOID_DIR="$SCRIPT_DIR/plasmoid"
OUT="$SCRIPT_DIR/gpu-boost-toggle.plasmoid"

command -v zip >/dev/null 2>&1 || {
	echo "Error: zip not found. Install your distro's zip package first." >&2
	exit 1
}

[ -d "$PLASMOID_DIR" ] || {
	echo "Error: missing $PLASMOID_DIR" >&2
	exit 1
}

rm -f "$OUT"

# kpackagetool6 expects metadata.json at the zip root, not nested inside
# a "plasmoid/" entry, so we cd into the directory before zipping.
(cd "$PLASMOID_DIR" && zip -r -X "$OUT" . -x '.*') >/dev/null

echo "Built $OUT"
