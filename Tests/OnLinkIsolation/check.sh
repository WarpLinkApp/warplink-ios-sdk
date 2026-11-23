#!/bin/sh
# Builds the sample package: `onLink` callers and readers in Swift 5 mode, and
# in Swift 6 mode with default main-actor isolation. Fails if either stops
# compiling. Skips when the Swift tools are older than the sample needs.
set -eu
cd "$(dirname "$0")"

version=$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9]*\)\.\([0-9]*\).*/\1 \2/p' | head -n 1)
major=${version%% *}
minor=${version##* }
if [ -n "$version" ] && { [ "$major" -lt 6 ] || { [ "$major" -eq 6 ] && [ "$minor" -lt 2 ]; }; }; then
  echo "Skipping the onLink isolation check: it needs Swift tools 6.2 (Xcode 26), found Swift $major.$minor."
  exit 0
fi

# One scratch path per checkout, so builds from two worktrees never share a lock.
scratch="${TMPDIR:-/tmp}/warplink-onlink-isolation-$(pwd -P | cksum | cut -d ' ' -f 1)"
swift build --scratch-path "$scratch"
