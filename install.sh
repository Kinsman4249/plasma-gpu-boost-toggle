#!/usr/bin/env bash
#
# install.sh - one-time interactive installer for GPU Boost Toggle's
# root-owned files (the helper script and the polkit policy).
#
# This script only handles the two files that need root. The plasmoid
# itself is not installed here: build it with ./build-plasmoid.sh and
# then either run `kpackagetool6 -t Plasma/Applet -i gpu-boost-toggle.plasmoid`
# or use Plasma's "Add Widgets > Get New... > Install Widget From Local
# File..." dialog to install the resulting .plasmoid file. That lets you
# update the widget on its own, without re-running this script or sudo.
#
# Root file operations use sudo interactively (you will be prompted for
# your password); this script never tries to write those files
# passwordlessly.
#
# Safe to re-run: every step below overwrites its own target cleanly.

set -euo pipefail

# Resolve paths relative to this script's own location, so it works no
# matter which directory you run it from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HELPER_SRC="$SCRIPT_DIR/gpu-boost-helper.sh"
HELPER_DEST="/usr/local/bin/gpu-boost-helper.sh"

# /usr/share/polkit-1/actions lives on the read-only /usr tree on
# ostree-based systems (Bazzite, Silverblue, etc.), so writing there always
# fails even as root. polkit also scans /usr/local/share/polkit-1/actions
# (see `man polkit`), and /usr/local is writable on those systems, so we
# install there instead. This works identically on traditional
# (non-ostree) distros too, since polkit checks that path everywhere.
POLICY_SRC="$SCRIPT_DIR/com.kinsman4249.gpuboost.policy"
POLICY_DEST="/usr/local/share/polkit-1/actions/com.kinsman4249.gpuboost.policy"

# Plasma's widget explorer, config-page sidebar, and panel icon all
# resolve icons through the user's icon theme (QIcon::fromTheme), not by
# reading files bundled inside the plasmoid package directly - see
# https://develop.kde.org/docs/plasma/widget/properties/ ("Icon" only
# accepts icon-theme names). So the plasmoid's custom icon has to be
# installed here too, independent of however the widget package itself
# gets installed (kpackagetool6 or the "Install Widget From Local File"
# dialog), or metadata.json's Icon reference to it would 404 into a
# generic broken-image icon instead of falling back to something valid.
ICON_SRC="$SCRIPT_DIR/plasmoid/contents/icons/com.kinsman4249.gpuboosttoggle.svg"
ICON_DEST_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
ICON_DEST="$ICON_DEST_DIR/com.kinsman4249.gpuboosttoggle.svg"

fail() {
	echo "Error: $1" >&2
	exit 1
}

step() {
	echo
	echo "==> $1"
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

step "Checking prerequisites"

command -v nvidia-smi >/dev/null 2>&1 \
	|| fail "nvidia-smi not found. Install your distro's NVIDIA driver package first."
echo "  nvidia-smi found: $(command -v nvidia-smi)"

command -v pkexec >/dev/null 2>&1 \
	|| fail "pkexec not found. This requires polkit."
echo "  pkexec found: $(command -v pkexec)"

command -v pkaction >/dev/null 2>&1 \
	|| fail "polkit tools not found. Is polkit installed?"

[ -f "$HELPER_SRC" ] || fail "missing $HELPER_SRC"
[ -f "$POLICY_SRC" ] || fail "missing $POLICY_SRC"
[ -f "$ICON_SRC" ] || fail "missing $ICON_SRC"

# ---------------------------------------------------------------------------
# Root file placement (interactive sudo, one prompt per step)
# ---------------------------------------------------------------------------

step "Installing helper script to $HELPER_DEST (requires sudo)"
sudo install -o root -g root -m 0755 "$HELPER_SRC" "$HELPER_DEST" \
	|| fail "failed to install $HELPER_DEST"

step "Installing polkit policy to $POLICY_DEST (requires sudo)"
sudo install -D -o root -g root -m 0644 "$POLICY_SRC" "$POLICY_DEST" \
	|| fail "failed to install $POLICY_DEST"

# ---------------------------------------------------------------------------
# Icon install (no sudo: this lives entirely under the user's home)
# ---------------------------------------------------------------------------

step "Installing widget icon to $ICON_DEST"
install -D -m 0644 "$ICON_SRC" "$ICON_DEST" \
	|| fail "failed to install $ICON_DEST"

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
	gtk-update-icon-cache -q -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
	kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
fi

step "Done"
echo "Now install the widget itself (no sudo needed):"
echo "  ./build-plasmoid.sh"
echo "  kpackagetool6 -t Plasma/Applet -i gpu-boost-toggle.plasmoid"
echo "or drag gpu-boost-toggle.plasmoid into Plasma's Add Widgets >"
echo "Get New... > Install Widget From Local File... dialog."
echo
echo "Then add 'GPU Boost Toggle' to a panel: right-click the panel >"
echo "Add Widgets, then search for it. Open its settings to configure watt"
echo "values. The widget starts OFF and stays OFF until you click it; it"
echo "also resets to OFF on every reboot, by design."
