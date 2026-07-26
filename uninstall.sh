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
CHROME_HELPER_DEST="$HOME/.local/share/plasma-gpu-boost-toggle/chrome-boost-helper.sh"

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
# Best-effort: undo the "Advanced" boost axes (services, power profile).
#
# Unlike restore_default() above, this script has no access to the QML
# widget's own in-memory "was this actually running before boost" state,
# since that never gets persisted (see README). So the heuristic here is
# simpler and more conservative: if a given axis was enabled in settings
# and currently looks paused/maxed, put it back to the ordinary default
# (services running, "balanced" power profile) rather than trying to
# reconstruct exactly what the user had before.
# ---------------------------------------------------------------------------

get_advanced_config() {
	# Usage: get_advanced_config <key>. Same best-effort plain-text config
	# read as restore_default() above, just parameterized over the key and
	# pointed at the [Configuration][Advanced] section.
	local key="$1"
	local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
	[ -f "$config_file" ] || return 1
	awk -v plugin="$PLUGIN_ID" -v key="$key" '
		/^\[/ { section = $0 }
		/^plugin=/ {
			if ($0 == "plugin=" plugin) { target = section }
		}
		target != "" && section == target "[Configuration][Advanced]" && $0 ~ "^" key "=" {
			sub("^" key "=", "")
			print
			exit
		}
	' "$config_file"
}

step "Checking background services"

restore_services() {
	if ! command -v systemctl >/dev/null 2>&1; then
		echo "  systemctl not found, skipping."
		return
	fi

	if [ "$(get_advanced_config serviceIdlingEnabled)" != "true" ]; then
		echo "  Service idling was not enabled, nothing to restore."
		return
	fi

	if [ "$(get_advanced_config idleBaloo)" = "true" ]; then
		local baloo_bin=""
		if command -v balooctl6 >/dev/null 2>&1; then
			baloo_bin="balooctl6"
		elif command -v balooctl >/dev/null 2>&1; then
			baloo_bin="balooctl"
		fi
		if [ -n "$baloo_bin" ] && "$baloo_bin" status 2>/dev/null | grep -qi "not running\|suspended\|disabled"; then
			echo "  Resuming Baloo file indexer..."
			"$baloo_bin" resume || echo "  Warning: failed to resume Baloo."
		fi
	fi

	if [ "$(get_advanced_config idleAkonadi)" = "true" ] && command -v akonadictl >/dev/null 2>&1; then
		if ! akonadictl status >/dev/null 2>&1; then
			echo "  Starting Akonadi..."
			akonadictl start || echo "  Warning: failed to start Akonadi."
		fi
	fi

	local units=""
	[ "$(get_advanced_config idleKalarm)" = "true" ] && units="kalarm.service"
	local custom_units
	custom_units="$(get_advanced_config customIdleUnits)"
	if [ -n "$custom_units" ]; then
		units="$units $(echo "$custom_units" | tr ',\n' '  ')"
	fi
	units="$(echo "$units" | xargs)"
	if [ -n "$units" ]; then
		local unit
		for unit in $units; do
			if [ "$(systemctl --user is-active "$unit" 2>/dev/null)" != "active" ]; then
				echo "  Starting $unit..."
				systemctl --user start "$unit" 2>/dev/null \
					|| echo "  Warning: failed to start $unit (it may not exist on this system)."
			fi
		done
	fi
}

restore_services

step "Checking power profile"

restore_power_profile() {
	if ! command -v powerprofilesctl >/dev/null 2>&1; then
		echo "  powerprofilesctl not found, skipping."
		return
	fi

	if [ "$(get_advanced_config powerProfileEnabled)" != "true" ]; then
		echo "  Power profile switching was not enabled, nothing to restore."
		return
	fi

	# "|| true": this is a plain assignment statement, not the condition of
	# an if/while, so under "set -e" a nonzero exit here (e.g. the daemon
	# not responding) would otherwise abort the whole script mid-uninstall,
	# skipping plasmoid/root-file removal entirely.
	local current
	current="$(powerprofilesctl get 2>/dev/null || true)"
	if [ "$current" = "performance" ]; then
		echo "  Restoring power profile to balanced (was left at performance)..."
		powerprofilesctl set balanced 2>/dev/null || echo "  Warning: failed to restore power profile."
	else
		echo "  Power profile is not at performance, nothing to restore."
	fi
}

restore_power_profile

step "Checking browser priority"

restore_chrome() {
	if [ "$(get_advanced_config chromeIdlingEnabled)" != "true" ]; then
		echo "  Browser deprioritizing was not enabled, nothing to restore."
		return
	fi
	if [ ! -x "$CHROME_HELPER_DEST" ]; then
		echo "  Chrome helper not installed, skipping."
		return
	fi

	local pattern
	pattern="$(get_advanced_config chromeProcessPattern)"
	if [ -z "$pattern" ]; then
		echo "  No saved process pattern, skipping."
		return
	fi

	echo "  Restoring default nice/IO priority for processes matching '$pattern'..."
	"$CHROME_HELPER_DEST" off "$pattern" 2>/dev/null \
		|| echo "  Warning: failed to restore browser priority."
}

restore_chrome

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

step "Removing browser-deprioritize helper $CHROME_HELPER_DEST"
if [ -e "$CHROME_HELPER_DEST" ]; then
	rm -f "$CHROME_HELPER_DEST"
else
	echo "  Not present, skipping."
fi

step "Done"
echo "The plasmoid's saved settings (watt values, debug flag, service/power"
echo "profile options) were left in place under your Plasma config directory."
echo "See README.md if you want to remove those too."
