#!/usr/bin/env bash
#
# gpu-boost-helper.sh
#
# Runs as root via pkexec, invoked by the GPU Boost Toggle plasmoid (see
# plasmoid/contents/ui/main.qml). Because this script runs with root
# privileges, argument validation below is a real security boundary, not
# a formality: treat anything that does not match exactly what is
# expected as hostile input and refuse it.
#
# No wattage numbers are hardcoded here. The caller (the plasmoid, using
# its own user-configured values) always passes the target wattage as an
# argument, and this script validates it against THIS GPU's own reported
# power.min_limit/power.max_limit (from nvidia-smi), not a fixed band, so
# a card whose real envelope falls outside some arbitrary guess is still
# handled correctly.
#
# Usage:
#   gpu-boost-helper.sh on <watts>      set persistence mode on, power limit <watts>
#   gpu-boost-helper.sh off <watts>     set power limit <watts>, persistence mode off
#   gpu-boost-helper.sh status          print "power.limit, persistence_mode"

set -euo pipefail

usage() {
	echo "Usage: $0 <on|off> <watts>" >&2
	echo "       $0 status" >&2
	exit 1
}

if [ "$#" -lt 1 ]; then
	usage
fi

mode="$1"

case "$mode" in
	on|off) [ "$#" -eq 2 ] || usage ;;
	status) [ "$#" -eq 1 ] || usage ;;
	*)
		echo "Error: mode must be one of: on, off, status" >&2
		usage
		;;
esac

# Rely on pkexec's own sanitized, minimal PATH rather than hardcoding an
# install path, so this works regardless of where the distro put the
# NVIDIA driver tools.
if ! command -v nvidia-smi >/dev/null 2>&1; then
	echo "Error: nvidia-smi not found in PATH" >&2
	exit 1
fi

if [ "$mode" = "on" ] || [ "$mode" = "off" ]; then
	watts="$2"
	# Strict check: digits only. No sign, no decimal point, no
	# leading/trailing junk that a looser regex might let through.
	if ! [[ "$watts" =~ ^[0-9]+$ ]]; then
		echo "Error: watts must be a plain positive integer, got '$watts'" >&2
		exit 1
	fi

	# Ask THIS card what it actually supports rather than trusting a
	# guessed-at band. power.min_limit/power.max_limit reflect the real,
	# per-GPU enforceable range (which varies a lot across models), so
	# that is the only source of truth for what "in range" means here.
	limits="$(nvidia-smi --query-gpu=power.min_limit,power.max_limit --format=csv,noheader,nounits | head -n1)"
	min_watts="$(echo "$limits" | cut -d',' -f1 | tr -d ' ')"
	max_watts="$(echo "$limits" | cut -d',' -f2 | tr -d ' ')"
	if ! [[ "$min_watts" =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! [[ "$max_watts" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
		echo "Error: could not read power.min_limit/power.max_limit from nvidia-smi" >&2
		exit 1
	fi
	# Compare with awk since limits can be fractional (e.g. "50.00") while
	# watts is a plain integer.
	if ! awk -v w="$watts" -v lo="$min_watts" -v hi="$max_watts" \
		'BEGIN { exit !(w >= lo && w <= hi) }'; then
		echo "Error: watts must be between ${min_watts} and ${max_watts} for this GPU, got '$watts'" >&2
		exit 1
	fi
fi

case "$mode" in
	on)
		nvidia-smi -pm 1 && nvidia-smi -pl "$watts"
		;;
	off)
		nvidia-smi -pl "$watts" && nvidia-smi -pm 0
		;;
	status)
		# enforced.power.limit, not power.limit: power.limit reports "[N/A]"
		# on some cards until nvidia-smi -pl has run at least once since
		# boot, which made this print a useless value on a freshly booted
		# machine.
		nvidia-smi --query-gpu=enforced.power.limit,persistence_mode --format=csv,noheader
		;;
esac

if [ "$mode" = "on" ] || [ "$mode" = "off" ]; then
	# "nvidia-smi -pl" exits 0 even when the driver refuses the change
	# outright (printed as "Changing power management limit is not
	# supported for GPU: ...", then "Treating as warning and moving on.").
	# This is common on laptop/mobile GPUs, where the OEM's own firmware
	# owns power management instead of exposing it through nvidia-smi. So
	# exit code alone cannot tell the caller whether this actually worked;
	# re-read the real enforced limit and compare against what was asked
	# for.
	actual="$(nvidia-smi --query-gpu=enforced.power.limit --format=csv,noheader,nounits | tr -d ' ')"
	if ! awk -v a="$actual" -v w="$watts" 'BEGIN { exit !(a >= w - 1 && a <= w + 1) }'; then
		echo "Error: GPU did not accept power limit ${watts}W (still at ${actual}W)." >&2
		echo "This GPU/driver may not support changing the power limit at all -" >&2
		echo "common on laptop GPUs, where the OEM's own firmware (not nvidia-smi)" >&2
		echo "controls power management." >&2
		exit 3
	fi
fi
