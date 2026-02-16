#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGE_FILE="$REPO_ROOT/modules/stability-matrix.nix"

echo "🔍 Checking for StabilityMatrix updates..."

echo "📡 Fetching latest release from GitHub..."
LATEST_INFO=$(curl -s https://api.github.com/repos/LykosAI/StabilityMatrix/releases/latest)
LATEST_TAG=$(echo "$LATEST_INFO" | jq -r '.tag_name')
LATEST_VERSION="${LATEST_TAG#v}"
LATEST_URL=$(echo "$LATEST_INFO" | jq -r '.html_url')

echo "📦 Latest version: $LATEST_VERSION"
echo "🔗 Release page: $LATEST_URL"

CURRENT_VERSION=$(grep -oP 'version = "\K[^"]+' "$PACKAGE_FILE" || echo "unknown")

echo "📌 Current version: $CURRENT_VERSION"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ] && [ "${FORCE_UPDATE:-false}" != "true" ]; then
  echo "✅ Already up to date!"
  exit 0
fi

echo "⬆️  New version available: $CURRENT_VERSION → $LATEST_VERSION"

echo "🔐 Calculating hash for v${LATEST_VERSION}..."
DOWNLOAD_URL="https://github.com/LykosAI/StabilityMatrix/releases/download/${LATEST_TAG}/StabilityMatrix-linux-x64.zip"
NEW_HASH=$(nix-prefetch-url --type sha256 "$DOWNLOAD_URL" 2>&1 | tail -1)

echo "📝 Updating package file..."

sed -i "s/version = \"[^\"]*\"/version = \"${LATEST_VERSION}\"/" "$PACKAGE_FILE"

sed -i "s/sha256 = \"[^\"]*\"/sha256 = \"${NEW_HASH}\"/" "$PACKAGE_FILE

echo "✨ Update complete: $LATEST_VERSION"
echo "🔗 Release: $LATEST_URL"

cat <<EOF > /tmp/stability-matrix-update-summary.txt
Version: $LATEST_VERSION
Previous: $CURRENT_VERSION
Release: $LATEST_URL
Hash: $NEW_HASH
EOF

cat /tmp/stability-matrix-update-summary.txt
