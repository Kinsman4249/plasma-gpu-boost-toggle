#!/usr/bin/env bash
#
# uninstall.sh - reverses install.sh exactly.
#
# Order matters: if the GPU is currently boosted, we bring it back down to
# its default power limit (using pkexec + the helper script) BEFORE
# removing that helper script, so we are never left needing a tool we
# just deleted. Every step after that mirrors install.sh in reverse.
#
# This does NOT touch the plasmoid's saved settings (watt values, debug
# flag). Those live under your Plasma config directory, out of scope for
# this script - see README.md.

set -euo pipefail

PLUGIN_ID="com.kinsman4249.gpuboosttoggle"
HELPER_DEST="/usr/local/bin/gpu-boost-helper.sh"
POLICY_DEST="/usr/share/polkit-1/actions/com.kinsman4249.gpuboost.policy"

fail() {
	echo "Error: $1" >&2
	exit 1
}

step() {
	echo
	echo "==> $1"
}

# ---------------------------------------------------------------------------
# Best-effort: bring the GPU back to its default power limit first.
# ---------------------------------------------------------------------------

step "Checking current GPU state"

restore_default() {
	if ! command -v nvidia-smi >/dev/null 2>&1; then
		echo "  nvidia-smi not found, skipping (nothing to restore)."
		return
	fi
	if [ ! -x "$HELPER_DEST" ]; then
		echo "  Helper script not installed, skipping."
		return
	fi

	local status
	if ! status="$(nvidia-smi --query-gpu=power.limit,persistence_mode --format=csv,noheader 2>/dev/null)"; then
		echo "  Could not read GPU state, skipping."
		return
	fi

	local persistence
	persistence="$(echo "$status" | cut -d, -f2)"
	if [[ "$persistence" != *Enabled* ]]; then
		echo "  GPU is not in BOOST state (persistence mode is off). Nothing to restore."
		return
	fi

	echo "  GPU appears to be boosted (persistence mode is on)."

	# Best-effort lookup of the plasmoid's saved "defaultWatts" value from
	# the Plasma config file. This is a plain-text config format, not a
	# stable API, so treat any failure here as "can't read it" and skip
	# gracefully rather than guessing a wattage.
	local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
	if [ ! -f "$config_file" ]; then
		echo "  Could not find Plasma config file ($config_file), skipping restore."
		echo "  Run 'sudo nvidia-smi -pl <watts> && sudo nvidia-smi -pm 0' manually if needed."
		return
	fi

	local default_watts
	default_watts="$(awk -v plugin="$PLUGIN_ID" '
		/^\[/ { section = $0 }
		/^plugin=/ {
			if ($0 == "plugin=" plugin) { target = section }
		}
		target != "" && section == target "[Configuration][General]" && /^defaultWatts=/ {
			sub(/^defaultWatts=/, "")
			print
			exit
		}
	' "$config_file")"

	if ! [[ "$default_watts" =~ ^[0-9]+$ ]] || [ "$default_watts" -eq 0 ]; then
		echo "  Could not find a saved default wattage, skipping restore."
		echo "  Run 'sudo nvidia-smi -pl <watts> && sudo nvidia-smi -pm 0' manually if needed."
		return
	fi

	echo "  Restoring default power limit ($default_watts W) before uninstalling (requires sudo)..."
	if pkexec "$HELPER_DEST" off "$default_watts"; then
		echo "  Restored."
	else
		echo "  Warning: failed to restore default power limit. You may need to run"
		echo "  'sudo nvidia-smi -pl $default_watts && sudo nvidia-smi -pm 0' manually."
	fi
}

restore_default

# ---------------------------------------------------------------------------
# Remove the plasmoid (user-level, no root needed)
# ---------------------------------------------------------------------------

step "Removing plasmoid via kpackagetool6"
if command -v kpackagetool6 >/dev/null 2>&1; then
	if kpackagetool6 -t Plasma/Applet --list 2>/dev/null | grep -q "$PLUGIN_ID"; then
		kpackagetool6 -t Plasma/Applet -r "$PLUGIN_ID" \
			|| fail "kpackagetool6 removal failed"
	else
		echo "  Plasmoid not installed, skipping."
	fi
else
	echo "  kpackagetool6 not found, skipping plasmoid removal."
fi

# ---------------------------------------------------------------------------
# Root file removal (interactive sudo, one prompt per step)
# ---------------------------------------------------------------------------

step "Removing helper script $HELPER_DEST (requires sudo)"
if [ -e "$HELPER_DEST" ]; then
	sudo rm -f "$HELPER_DEST" || fail "failed to remove $HELPER_DEST"
else
	echo "  Not present, skipping."
fi

step "Removing polkit policy $POLICY_DEST (requires sudo)"
if [ -e "$POLICY_DEST" ]; then
	sudo rm -f "$POLICY_DEST" || fail "failed to remove $POLICY_DEST"
else
	echo "  Not present, skipping."
fi

step "Done"
echo "The plasmoid's saved settings (watt values, debug flag) were left in"
echo "place under your Plasma config directory. See README.md if you want"
echo "to remove those too."
