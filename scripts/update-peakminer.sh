#!/usr/bin/env bash
# Update peakminer to the latest (or specified) version
# Usage: ./scripts/update-peakminer.sh [version]
# Example: ./scripts/update-peakminer.sh 1.0.12

set -euo pipefail

PACKAGE_FILE="packages/peakminer.nix"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$REPO_DIR"

# Get current version
CURRENT=$(grep 'version ?=' "$PACKAGE_FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "Current peakminer version: $CURRENT"

# Determine target version
if [ -n "${1:-}" ]; then
  TARGET="$1"
else
  echo "Querying GitHub for latest release..."
  LATEST_TAG=$(curl -sf https://api.github.com/repos/peakminer/peakminer/releases/latest | jq -r '.tag_name')
  TARGET="${LATEST_TAG#v}"
fi

echo "Target version: $TARGET"

if [ "$CURRENT" = "$TARGET" ]; then
  echo "Already on $TARGET, nothing to do."
  exit 0
fi

echo "Updating $CURRENT → $TARGET"

# Update version in package file
sed -i "s/version ?= \".*\"/version ?= \"$TARGET\"/" "$PACKAGE_FILE"

# Build to get hash mismatch (which tells us the correct hash)
echo "Building to compute new hash..."
BUILD_OUTPUT=$(nix build .#peakminer --no-link 2>&1 || true)
NEW_HASH=$(echo "$BUILD_OUTPUT" | grep 'got:' | sed 's/.*got: *//' | head -1 | tr -d ' ')

if [ -z "$NEW_HASH" ]; then
  echo "ERROR: Could not determine new hash. Build output:"
  echo "$BUILD_OUTPUT"
  exit 1
fi

echo "New hash: $NEW_HASH"
sed -i "s|hash = \".*\";|hash = \"$NEW_HASH\";|" "$PACKAGE_FILE"

# Verify build
echo "Verifying build..."
nix build .#peakminer --no-link --print-out-paths

# Verify binary
PEAKMINER_PATH=$(nix build .#peakminer --no-link --print-out-paths)
echo "Binary verification:"
"$PEAKMINER_PATH/bin/peakminer" --version

echo ""
echo "SUCCESS: peakminer updated to $TARGET"
echo ""
echo "Next steps:"
echo "  1. Test on one GPU: systemd-run --unit=pm-test ... peakminer ..."
echo "  2. Verify shares flow: journalctl -u pm-test | grep 'last share'"
echo "  3. Commit: git add -A && git commit -m 'feat(peakminer): update to v$TARGET'"
echo "  4. Deploy: just deploy"
