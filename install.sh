#!/usr/bin/env bash
#
# install.sh - one-time interactive installer for GPU Boost Toggle.
#
# Copies the root-owned helper script and polkit policy into place, then
# installs the plasmoid itself for the current user. Root file operations
# use sudo interactively (you will be prompted for your password); this
# script never tries to write those files passwordlessly.
#
# Safe to re-run: every step below overwrites its own target cleanly.

set -euo pipefail

# Resolve paths relative to this script's own location, so it works no
# matter which directory you run it from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HELPER_SRC="$SCRIPT_DIR/gpu-boost-helper.sh"
HELPER_DEST="/usr/local/bin/gpu-boost-helper.sh"

POLICY_SRC="$SCRIPT_DIR/com.kinsman4249.gpuboost.policy"
POLICY_DEST="/usr/share/polkit-1/actions/com.kinsman4249.gpuboost.policy"

PLASMOID_DIR="$SCRIPT_DIR/plasmoid"

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

command -v kpackagetool6 >/dev/null 2>&1 \
	|| fail "kpackagetool6 not found. This requires KDE Plasma 6."
echo "  kpackagetool6 found: $(command -v kpackagetool6)"

command -v pkexec >/dev/null 2>&1 \
	|| fail "pkexec not found. This requires polkit."
echo "  pkexec found: $(command -v pkexec)"

[ -d /usr/share/polkit-1/actions ] \
	|| fail "/usr/share/polkit-1/actions does not exist. Is polkit installed?"

[ -f "$HELPER_SRC" ] || fail "missing $HELPER_SRC"
[ -f "$POLICY_SRC" ] || fail "missing $POLICY_SRC"
[ -d "$PLASMOID_DIR" ] || fail "missing $PLASMOID_DIR"

# ---------------------------------------------------------------------------
# Root file placement (interactive sudo, one prompt per step)
# ---------------------------------------------------------------------------

step "Installing helper script to $HELPER_DEST (requires sudo)"
sudo install -o root -g root -m 0755 "$HELPER_SRC" "$HELPER_DEST" \
	|| fail "failed to install $HELPER_DEST"

step "Installing polkit policy to $POLICY_DEST (requires sudo)"
sudo install -o root -g root -m 0644 "$POLICY_SRC" "$POLICY_DEST" \
	|| fail "failed to install $POLICY_DEST"

# ---------------------------------------------------------------------------
# Plasmoid install (user-level, no root needed)
# ---------------------------------------------------------------------------

step "Installing plasmoid via kpackagetool6"
if kpackagetool6 -t Plasma/Applet --list 2>/dev/null | grep -q "com.kinsman4249.gpuboosttoggle"; then
	echo "  Already installed, upgrading..."
	kpackagetool6 -t Plasma/Applet -u "$PLASMOID_DIR" \
		|| fail "kpackagetool6 upgrade failed"
else
	kpackagetool6 -t Plasma/Applet -i "$PLASMOID_DIR" \
		|| fail "kpackagetool6 install failed"
fi

step "Done"
echo "Add 'GPU Boost Toggle' to a panel: right-click the panel > Add Widgets,"
echo "then search for it. Open its settings to configure watt values."
echo "The widget starts OFF and stays OFF until you click it; it also resets"
echo "to OFF on every reboot, by design."
