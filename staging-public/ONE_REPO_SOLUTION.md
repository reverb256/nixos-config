# One-Repo Solution: Git Filter and Staging Approach

## The Best Approach: Git-Filter with Staging

You can maintain full functionality in your single private repo while having a sanitized "staging" area that can be published to public mirrors. Here's how:

## 🏗️ Architecture: Staging Area Approach

```
/etc/nixos/ (Private repo - full functionality)
├── .git/
├── hosts/              # Private configs with real IPs
├── modules/            # Public + private infrastructure patterns  
├── secrets/            # Encrypted secrets
├── scripts/
│   ├── sanitize-for-public.sh    # Script to create sanitized staging
│   └── publish-to-public.sh      # Script to push to public repo
├── staging-public/     # Staging area (gitignored) - sanitized versions
└── .gitignore          # Ignores staging-public/
```

## 🤖 Automation Scripts

### 1. Sanitization Script
```bash
# scripts/sanitize-for-public.sh
#!/usr/bin/env bash

set -e

STAGING_DIR="./staging-public"
PUBLIC_BRANCH="public-staging"

echo "Creating sanitized staging area..."

# Create or clean staging directory
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy all relevant files except sensitive ones
rsync -av \
    --include="*/" \
    --include="*.nix" \
    --include="*.md" \
    --include="flake.nix" \
    --include="justfile" \
    --exclude="*" \
    . "$STAGING_DIR/"

# Sanitize private information
find "$STAGING_DIR" -name "*.nix" -type f -exec sed -i \
    -e 's/10\.1\.1\.[0-9]\+/192.168.100.X/g' \
    -e 's/100\.[0-9]\+\.[0-9]\+\.[0-9]\+/100.YYY.YYY.YYY/g' \
    -e 's/krxXVNVMM7\.[a-z0-9.-]*/WALLET_PREFIX.NODE_NAME/g' \
    -e 's/ssh-ed25519 [A-Za-z0-9+/=]* [^@]*@[a-zA-Z0-9-]*/ssh-ed25519 XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX USERNAME@HOST/g' \
    -e 's/"WORKER_X"\|"WORKER_X"\|"WORKER_X"\|"WORKER_X"/"WORKER_X"/g' \
    -e 's/USERNAME@HOST[a-zA-Z0-9-]*/USERNAME@HOST/g' \
    '{}' \;

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
```

### 2. Publication Script
```bash
# scripts/publish-to-public.sh
#!/usr/bin/env bash

set -e

STAGING_DIR="./staging-public"
PUBLIC_REMOTE="git@github.com:YOUR_USERNAME/public-nixos-infrastructure.git"  # Update this

if [ ! -d "$STAGING_DIR" ]; then
    echo "Error: Staging directory $STAGING_DIR does not exist"
    echo "Run scripts/sanitize-for-public.sh first"
    exit 1
fi

echo "Publishing sanitized content to public repo..."

# Create temporary directory for git operations
TEMP_GIT=$(mktemp -d)
cd "$TEMP_GIT"

# Initialize git repo for public content
git init
git remote add origin "$PUBLIC_REMOTE"

# Copy sanitized files
cp -r "$PWD/../../$STAGING_DIR"/* .

# Add all files
git add .

# Check if there are changes to commit
if [ -n "$(git status --porcelain)" ]; then
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git commit -m "Publish sanitized infrastructure patterns: $(date -Iseconds)"
    git push -f origin main
    echo "Public repository updated successfully!"
else
    echo "No changes to publish."
fi

# Cleanup
rm -rf "$TEMP_GIT"

echo "Publication complete!"
```

## 🔄 Integration with Your Current Workflow

### 1. No Changes to Your Current Setup
- Your `just cluster-deploy` continues to work unchanged
- Your GitHub Actions continue validating private configurations
- Your secrets and private values remain private

### 2. Optional Publishing
Only run sanitization/publishing when you want to share public content:

```bash
# When you want to publish to public repo:
./scripts/sanitize-for-public.sh
./scripts/publish-to-public.sh
```

## 🛡️ Safety Features

### Pre-commit Hooks
Add to `.git/hooks/pre-commit`:
```bash
#!/usr/bin/env bash

# Ensure no private data is accidentally committed to public staging
if [ -d "staging-public" ]; then
    # Check that staging-public is properly sanitized
    if grep -r "10\.1\.1\." staging-public/ || grep -r "krxXVNVMM7\." staging-public/; then
        echo "ERROR: Private data detected in staging-public/"
        exit 1
    fi
fi

exit 0
```

## 🚀 One-Command Solution

Create a convenience script that does everything:

```bash
# scripts/release-public.sh
#!/usr/bin/env bash

set -e

echo "=== Creating sanitized public release ==="

# Sanitize the content
./scripts/sanitize-for-public.sh

# Validate the sanitized output
echo "Validating sanitized content..."
if grep -r "10\.1\.1\." staging-public/ || grep -r "krxXVNVMM7\." staging-public/; then
    echo "ERROR: Private data still found in sanitized output!"
    exit 1
fi

echo "✅ Sanitized content is clean."

# Optional: Publish automatically
if [ $# -gt 0 ] && [ "$1" = "--publish" ]; then
    ./scripts/publish-to-public.sh
fi

echo "=== Sanitized release ready in staging-public/ ==="
echo "Run 'scripts/publish-to-public.sh' to make it public,"
echo "or inspect staging-public/ before publishing."
```

## 🎯 Benefits

✅ **One repo**: Full functionality without splitting repos
✅ **No CI/CD changes**: Your current workflow continues unchanged  
✅ **On-demand publishing**: Share publicly when you choose
✅ **Safety**: Automated checks prevent accidental disclosure
✅ **Flexibility**: Can adapt the sanitization as needed
✅ **Transparency**: Clear separation between private and public content

## 📋 Setup

1. Add the scripts to your `scripts/` directory
2. Add `staging-public/` to your `.gitignore`
3. Customize the `PUBLIC_REMOTE` in `publish-to-public.sh`
4. Your current functionality remains completely unchanged

This gives you the best of both worlds: full private functionality with optional public sharing capability!