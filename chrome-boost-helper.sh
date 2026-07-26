#!/usr/bin/env bash
#
# chrome-boost-helper.sh
#
# Runs as the ordinary desktop user (never root, never through pkexec),
# invoked by the GPU Boost Toggle plasmoid (see
# plasmoid/contents/ui/ChromeController.qml). It deprioritizes whatever
# browser processes match a user-configured pattern so a game gets first
# call on the CPU/disk, and makes a one-shot attempt to push that
# browser's idle memory out to swap/cache via cgroup v2's memory.reclaim.
#
# No root is needed for any of this:
#   - renice/ionice only ever need root to RAISE another process's
#     priority, or to touch a process you don't own. Lowering your own
#     process's priority is always allowed.
#   - memory.reclaim on a systemd-delegated user cgroup (app.slice, etc.)
#     is writable by the owning user - see the README's Security notes.
#
# Because this still runs with the invoking user's real privileges
# (nothing elevated), argument validation here is about correctness and
# not accidentally matching/touching the wrong processes - not a security
# boundary the way gpu-boost-helper.sh's is.
#
# Usage:
#   chrome-boost-helper.sh on <nice 0-19> <pattern>
#   chrome-boost-helper.sh off <pattern>
#
# <pattern> is an extended-regex (grep -E) pattern matched against the
# full command line (pgrep -f), e.g. "chrome|chromium|brave".

set -uo pipefail
# Deliberately not "set -e": this script talks to several optional,
# independent subsystems (pgrep, renice, ionice, cgroupfs) where any one
# of them failing (a process exiting mid-loop, a cgroup that isn't
# delegated, etc.) should not abort the rest - each step is already
# best-effort and checks its own exit status where it matters.

usage() {
	echo "Usage: $0 on <nice 0-19> <pattern>" >&2
	echo "       $0 off <pattern>" >&2
	exit 1
}

if [ "$#" -lt 1 ]; then
	usage
fi

mode="$1"

case "$mode" in
	on) [ "$#" -eq 3 ] || usage ;;
	off) [ "$#" -eq 2 ] || usage ;;
	*)
		echo "Error: mode must be one of: on, off" >&2
		usage
		;;
esac

# Only characters that make sense in an extended-regex alternation of
# process names - no shell metacharacters, since this is passed to
# pgrep/grep as a pattern, never through eval or a constructed shell
# string.
pattern="$([ "$mode" = "on" ] && echo "$3" || echo "$2")"
if ! [[ "$pattern" =~ ^[A-Za-z0-9._|-]+$ ]]; then
	echo "Error: pattern contains characters outside [A-Za-z0-9._|-], got '$pattern'" >&2
	exit 1
fi

if [ "$mode" = "on" ]; then
	nice_value="$2"
	if ! [[ "$nice_value" =~ ^[0-9]+$ ]] || [ "$nice_value" -gt 19 ]; then
		echo "Error: nice value must be an integer from 0 to 19, got '$nice_value'" >&2
		exit 1
	fi
fi

command -v pgrep >/dev/null 2>&1 || { echo "Error: pgrep not found in PATH" >&2; exit 1; }

# Space-separated, not an array: this only ever feeds into other
# commands' argument lists via word-splitting, and pgrep -f already
# guarantees each PID is plain digits.
#
# "grep -v -x $$": pgrep -f matches against the FULL command line, and
# this script's own argv literally contains $pattern (it was passed in as
# an argument) - so without this exclusion, the script always matches
# its own PID too.
pids="$(pgrep -f -- "$pattern" | grep -v -x "$$" | tr '\n' ' ')"
if [ -z "${pids// /}" ]; then
	echo "No processes matched pattern '$pattern'"
	exit 0
fi
echo "Matched processes (PIDs): $pids"

if [ "$mode" = "off" ]; then
	# Best-effort restore to the ordinary default nice/IO priority. This
	# does not track each process's original values (chrome-family
	# processes are always spawned at nice 0 / best-effort IO by their
	# parent browser, so "put it back to the normal default" is the
	# correct restore here, not a guess).
	# shellcheck disable=SC2086
	renice -n 0 -p $pids >/dev/null 2>&1
	# shellcheck disable=SC2086
	ionice -c 2 -n 4 -p $pids >/dev/null 2>&1
	echo "Restored default nice/IO priority for matched processes"
	exit 0
fi

# --- mode = on ---

# shellcheck disable=SC2086
if renice -n "$nice_value" -p $pids >/dev/null 2>&1; then
	echo "Reniced matched processes to $nice_value"
else
	echo "Warning: renice failed or was only partially applied (some processes may have exited)" >&2
fi

# Idle I/O class: this browser's disk activity only happens when nothing
# else wants the disk, which is exactly what "get out of the game's way"
# means for I/O, not just CPU.
# shellcheck disable=SC2086
if ionice -c 3 -p $pids >/dev/null 2>&1; then
	echo "Set idle I/O class for matched processes"
else
	echo "Warning: ionice failed or was only partially applied" >&2
fi

# One-shot memory push: for each matched PID, find its cgroup v2 path and
# only act on it if the cgroup's own name (the last path component)
# matches the same pattern. That check is the safety rail - it is what
# stops this from ever calling memory.reclaim on some shared parent slice
# (e.g. the whole user session) that happens to also contain other
# unrelated processes; systemd/flatpak/xdg-desktop-portal each scope one
# browser instance into its own uniquely-named unit, and this only fires
# when it recognizes that name.
declare -A seen_paths=()
reclaimed_any=0
for pid in $pids; do
	cgroup_line="$(awk -F: '$1==0{print $3}' "/proc/$pid/cgroup" 2>/dev/null)"
	[ -n "$cgroup_line" ] || continue
	[ -n "${seen_paths[$cgroup_line]:-}" ] && continue
	seen_paths[$cgroup_line]=1

	base="$(basename "$cgroup_line")"
	echo "$base" | grep -qiE -- "$pattern" || continue

	full="/sys/fs/cgroup${cgroup_line}"
	reclaim_file="$full/memory.reclaim"
	current_file="$full/memory.current"
	[ -w "$reclaim_file" ] || continue
	current="$(cat "$current_file" 2>/dev/null)"
	[[ "$current" =~ ^[0-9]+$ ]] || continue

	if echo "$current" > "$reclaim_file" 2>/dev/null; then
		echo "reclaimed:$base:$current"
		reclaimed_any=1
	fi
done

if [ "$reclaimed_any" -eq 0 ]; then
	echo "No dedicated cgroup found for matched processes - memory reclaim skipped"
fi

exit 0
