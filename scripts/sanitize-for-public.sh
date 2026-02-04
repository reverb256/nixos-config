#!/usr/bin/env bash

set -e

STAGING_DIR="./staging-public"
PUBLIC_BRANCH="public-staging"

echo "Creating sanitized staging area..."

# Create or clean staging directory
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy only the essential files (avoid copying git dirs and temp files)
rsync -av \
    --include="*/" \
    --include="*.nix" \
    --include="*.md" \
    --include="flake.nix" \
    --include="justfile" \
    --include="LICENSE" \
    --include="README.md" \
    --exclude="*" \
    . "$STAGING_DIR/" \
    --prune-empty-dirs

# Sanitize private information in .nix files
find "$STAGING_DIR" -name "*.nix" -type f -exec sed -i \
    -e 's/10\.1\.1\.[0-9]\+/192.168.100.X/g' \
    -e 's/100\.[0-9]\+\.[0-9]\+\.[0-9]\+/100.YYY.YYY.YYY/g' \
    -e 's/krxXVNVMM7\.[a-z0-9.-]*/WALLET_PREFIX.NODE_NAME/g' \
    -e 's/ssh-ed25519 [A-Za-z0-9+/=]* [^@]*@[a-zA-Z0-9-]*/ssh-ed25519 XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX USERNAME@HOST/g' \
    -e 's/"zephyr"\|"nexus"\|"forge"\|"sentry"/"WORKER_X"/g' \
    -e 's/j_kro@[a-zA-Z0-9-]*/USERNAME@HOST/g' \
    -e 's/10\.0\.0\.[0-9]\+/192.168.101.X/g' \
    -e 's/10\.1\.1\.1"/192.168.1.1"/g' \
    '{}' \;

# Sanitize private information in markdown files
find "$STAGING_DIR" -name "*.md" -type f -exec sed -i \
    -e 's/\b10\.1\.1\.[0-9]\+\b/192.168.100.X/g' \
    -e 's/\b100\.[0-9]\+\.[0-9]\+\.[0-9]\+\b/100.YYY.YYY.YYY/g' \
    -e 's/krxXVNVMM7\.[a-z0-9.-]*/WALLET_PREFIX.NODE_NAME/g' \
    -e 's/"zephyr"\|"nexus"\|"forge"\|"sentry"/"WORKER_X"/g' \
    -e 's/j_kro@[a-zA-Z0-9-]*/USERNAME@HOST/g' \
    -e 's/\b10\.0\.0\.[0-9]\+\b/192.168.101.X/g' \
    -e 's/\b10\.1\.1\.1\b/192.168.1.1/g' \
    '{}' \;

# Sanitize in justfile specifically
if [ -f "$STAGING_DIR/justfile" ]; then
    sed -i \
        -e 's/\b10\.1\.1\.[0-9]\+\b/192.168.100.X/g' \
        -e 's/\b100\.[0-9]\+\.[0-9]\+\.[0-9]\+\b/100.YYY.YYY.YYY/g' \
        -e 's/krxXVNVMM7\.[a-z0-9.-]*/WALLET_PREFIX.NODE_NAME/g' \
        -e 's/"zephyr"\|"nexus"\|"forge"\|"sentry"/"WORKER_X"/g' \
        -e 's/j_kro@[a-zA-Z0-9-]*/USERNAME@HOST/g' \
        "$STAGING_DIR/justfile"
fi

# Create public-friendly documentation
cat > "$STAGING_DIR/PUBLIC_USAGE.md" << 'EOF'
# Public Infrastructure Patterns

This repository contains infrastructure patterns extracted from a private deployment.

## Parameterization

To adapt for your environment:

1. Replace `192.168.100.X` with your internal IP range
2. Replace `WALLET_PREFIX.NODE_NAME` with your mining wallet IDs  
3. Replace `WORKER_X` with your hostnames
4. Update networking and other private configurations

See PARAMETERIZATION_BEST_PRACTICES.md for full documentation.
EOF

# Copy important public docs
cp README.md "$STAGING_DIR/" 2>/dev/null || true
cp LICENSE "$STAGING_DIR/" 2>/dev/null || true

echo "Sanitized staging area created in $STAGING_DIR/"
echo "Contents ready for public publication."

# Verify sanitization
echo "Verifying sanitization..."
if grep -r "10\.1\.1\." "$STAGING_DIR/" --include="*.nix" --include="*.md" --include="justfile" 2>/dev/null; then
    echo "⚠️  Warning: Some private IPs may still be present"
else
    echo "✅ No private IPs detected in sanitized output"
fi

if grep -r "krxXVNVMM7\." "$STAGING_DIR/" --include="*.nix" --include="*.md" --include="justfile" 2>/dev/null; then
    echo "⚠️  Warning: Some wallet IDs may still be present"
else
    echo "✅ No mining wallet IDs detected in sanitized output"
fi