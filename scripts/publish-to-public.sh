#!/usr/bin/env bash

set -e

STAGING_DIR="./staging-public"
PUBLIC_REMOTE="git@github.com:YOUR_USERNAME/public-nixos-infrastructure.git"  # Update this

if [ ! -d "$STAGING_DIR" ]; then
    echo "Error: Staging directory $STAGING_DIR does not exist"
    echo "Run scripts/sanitize-for-public.sh first"
    exit 1
fi

echo "=== Public Repository Publisher ==="
echo "This script publishes sanitized content to a public repository."
echo "IMPORTANT: Update PUBLIC_REMOTE in this script with your actual public repo URL."
echo ""
read -p "Do you want to continue? (y/N): " -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

read -p "Enter the public repository URL: " -r USER_PUBLIC_REMOTE

if [ -z "$USER_PUBLIC_REMOTE" ]; then
    echo "No URL provided. Exiting."
    exit 1
fi

echo "Publishing sanitized content to public repo: $USER_PUBLIC_REMOTE..."

# Create temporary directory for git operations
TEMP_GIT=$(mktemp -d)
cd "$TEMP_GIT"

# Initialize git repo for public content
git init
git remote add origin "$USER_PUBLIC_REMOTE"

# Copy sanitized files
cp -r "$PWD/../../$STAGING_DIR"/* .

# Add all files
git add .

# Check if there are changes to commit
if [ -n "$(git status --porcelain)" ]; then
    git config user.name "Auto Publisher"
    git config user.email "publisher@noreply.invalid"
    git commit -m "Publish sanitized infrastructure patterns: $(date -Iseconds)"
    git push -f origin main
    echo "✅ Public repository updated successfully!"
else
    echo "ℹ️ No changes to publish."
fi

# Cleanup
rm -rf "$TEMP_GIT"

echo "🎉 Publication complete!"
echo "Your sanitized content has been pushed to: $USER_PUBLIC_REMOTE"