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

# Without this rule, the policy's auth_admin_keep only caches your admin
# auth for a few minutes (polkit's fixed retention window, not something
# the .policy file can extend), so toggling again after a longer gap
# re-prompts for a password. This rule grants com.kinsman4249.gpuboost.toggle
# specifically - not admin rights generally - to specifically your user
# account, so it never has to prompt at all after this script runs once.
# The helper script itself still validates the on/off mode and the
# requested wattage against this GPU's real min/max range, so this only
# widens who can flip a bounded, non-destructive setting without a
# password, not what they can do with it.
POLKIT_RULE_DEST="/etc/polkit-1/rules.d/70-com.kinsman4249.gpuboost.rules"

# Plasma's widget explorer, config-page sidebar, and panel icon all
# resolve icons through the user's icon theme (QIcon::fromTheme / theme
# name), not by reading files bundled inside the plasmoid package
# directly - see https://develop.kde.org/docs/plasma/widget/properties/
# ("Icon" only accepts icon-theme names), and Kirigami.Icon in main.qml
# also rendered a raw file:// source as blank in the panel even though
# the same file loaded fine elsewhere. So all three of this widget's
# icons (brand icon, boost-on, boost-off) need to land in the user's
# icon theme, independent of however the widget package itself gets
# installed (kpackagetool6 or the "Install Widget From Local File"
# dialog).
ICON_SRC_DIR="$SCRIPT_DIR/plasmoid/contents/icons"
ICON_DEST_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
ICON_NAMES=(
	com.kinsman4249.gpuboosttoggle
	com.kinsman4249.gpuboosttoggle-on
	com.kinsman4249.gpuboosttoggle-off
)

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
for name in "${ICON_NAMES[@]}"; do
	[ -f "$ICON_SRC_DIR/$name.svg" ] || fail "missing $ICON_SRC_DIR/$name.svg"
done

# ---------------------------------------------------------------------------
# Root file placement (interactive sudo, one prompt per step)
# ---------------------------------------------------------------------------

step "Installing helper script to $HELPER_DEST (requires sudo)"
sudo install -o root -g root -m 0755 "$HELPER_SRC" "$HELPER_DEST" \
	|| fail "failed to install $HELPER_DEST"

step "Installing polkit policy to $POLICY_DEST (requires sudo)"
sudo install -D -o root -g root -m 0644 "$POLICY_SRC" "$POLICY_DEST" \
	|| fail "failed to install $POLICY_DEST"

step "Installing polkit no-password rule to $POLKIT_RULE_DEST (requires sudo)"
# NOT "install -d": /etc/polkit-1/rules.d already exists, owned
# root:polkitd so the polkitd daemon itself can read it. Recreating it
# with -o root -g root would silently strip that group and make polkitd
# unable to read the whole directory - not just this rule, every rule -
# so only create it if it is genuinely missing, and never touch its
# ownership if it already exists.
if [ ! -d "$(dirname "$POLKIT_RULE_DEST")" ]; then
	sudo install -d -o root -g polkitd -m 0750 "$(dirname "$POLKIT_RULE_DEST")"
fi
sudo tee "$POLKIT_RULE_DEST" >/dev/null <<RULES || fail "failed to install $POLKIT_RULE_DEST"
// Generated by install.sh for user "$USER" - grants only
// com.kinsman4249.gpuboost.toggle without a password, only to this one
// user account. Re-run install.sh after changing users to regenerate
// this for a different account; delete this file to go back to
// prompting (the policy's auth_admin_keep default).
polkit.addRule(function(action, subject) {
	if (action.id == "com.kinsman4249.gpuboost.toggle" &&
	    subject.user == "$USER") {
		return polkit.Result.YES;
	}
});
RULES
sudo chmod 0644 "$POLKIT_RULE_DEST"

# ---------------------------------------------------------------------------
# Icon install (no sudo: this lives entirely under the user's home)
# ---------------------------------------------------------------------------

step "Installing widget icons to $ICON_DEST_DIR"
for name in "${ICON_NAMES[@]}"; do
	install -D -m 0644 "$ICON_SRC_DIR/$name.svg" "$ICON_DEST_DIR/$name.svg" \
		|| fail "failed to install $ICON_DEST_DIR/$name.svg"
done

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
echo
echo "Toggling on/off will not prompt for a password: $POLKIT_RULE_DEST"
echo "grants that one action to your user account only. Delete that file"
echo "to go back to a password prompt on every toggle."
