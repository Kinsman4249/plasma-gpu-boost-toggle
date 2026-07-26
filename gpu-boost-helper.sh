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
# argument.
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
	on|off)
		if [ "$#" -ne 2 ]; then
			usage
		fi
		watts="$2"
		# Strict check: digits only. No sign, no decimal point, no
		# leading/trailing junk that a looser regex might let through.
		if ! [[ "$watts" =~ ^[0-9]+$ ]]; then
			echo "Error: watts must be a plain positive integer, got '$watts'" >&2
			exit 1
		fi
		# Sane power-envelope bound. Reject anything outside it rather
		# than trusting nvidia-smi to reject it for us.
		if [ "$watts" -lt 50 ] || [ "$watts" -gt 500 ]; then
			echo "Error: watts must be between 50 and 500, got '$watts'" >&2
			exit 1
		fi
		;;
	status)
		if [ "$#" -ne 1 ]; then
			usage
		fi
		;;
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

case "$mode" in
	on)
		nvidia-smi -pm 1 && nvidia-smi -pl "$watts"
		;;
	off)
		nvidia-smi -pl "$watts" && nvidia-smi -pm 0
		;;
	status)
		nvidia-smi --query-gpu=power.limit,persistence_mode --format=csv,noheader
		;;
esac
