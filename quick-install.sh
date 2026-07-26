#!/usr/bin/env bash
#
# quick-install.sh - fetched and run by the curl one-liner in the README.
#
# Does nothing privileged itself: it just clones the repo into a temp
# directory and hands off to the real install.sh, unmodified, so the
# review-before-running steps described in install.sh's own header still
# apply the same way they would to a manual git clone.

set -euo pipefail

REPO_URL="https://github.com/Kinsman4249/plasma-gpu-boost-toggle.git"

command -v git >/dev/null 2>&1 || {
    echo "git is required but not found. Install git and try again." >&2
    exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

git clone --depth 1 "$REPO_URL" "$TMP_DIR/plasma-gpu-boost-toggle"
exec "$TMP_DIR/plasma-gpu-boost-toggle/install.sh"
