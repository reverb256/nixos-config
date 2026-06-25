#!/usr/bin/env bash
# Run: bash update-srbminer.sh
set -euo pipefail
LATEST=$(curl -sS "https://api.github.com/repos/doktor83/SRBMiner-Multi/releases/latest" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['tag_name'])")
echo "Latest: $LATEST"
VERSION="${LATEST#v}"
HASH=$(nix-prefetch-url --type sha256 "https://github.com/doktor83/SRBMiner-Multi/releases/download/$LATEST/SRBMiner-Multi-${VERSION//./-}-Linux.tar.gz")
echo "Hash: sha256-$HASH"
sed -i "s/version = \".*\";/version = \"$VERSION\";/" "$(dirname "$0")/srbminer.nix"
sed -i "s|hash = \".*\";|hash = \"sha256-$HASH\";|" "$(dirname "$0")/srbminer.nix"
echo "Updated"
