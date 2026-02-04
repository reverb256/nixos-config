#!/usr/bin/env bash
# scripts/generate-public-mirror.sh

set -e

# Configuration
PRIVATE_REPO_ROOT="$(pwd)"
PUBLIC_WORKTREE="$PRIVATE_REPO_ROOT/../nixos-public"
PUBLIC_REMOTE="public-origin"  # The public GitHub repo

echo "Generating public mirror with sanitization..."

# Create worktree for public version (if it doesn't exist)
if [ ! -d "$PUBLIC_WORKTREE" ]; then
    echo "Creating public worktree at $PUBLIC_WORKTREE"
    git worktree add "$PUBLIC_WORKTREE" public-mirror
else
    # Update worktree
    (cd "$PUBLIC_WORKTREE" && git fetch origin && git reset --hard origin/main)
fi

# Sanitize the private repo content and copy to public worktree
sanitize_and_copy() {
    # Create temporary directory with sanitized content
    TEMP_SANITIZED=$(mktemp -d)
    
    # Copy all .nix files and sanitize them
    rsync -av --include="*/" --include="*.nix" --exclude="*" "$PRIVATE_REPO_ROOT/" "$TEMP_SANITIZED/" --prune-empty-dirs
    
    # Sanitize content
    find "$TEMP_SANITIZED" -name "*.nix" -type f -exec sed -i.bak \
        -e 's/10\.1\.1\.[0-9]\+/192.168.100.X/g' \
        -e 's/100\.[0-9]\+\.[0-9]\+\.[0-9]\+/100.YYY.YYY.YYY/g' \
        -e 's/krxXVNVMM7\.[a-z]*[0-9]*/WALLET_PREFIX.NODE_NAME/g' \
        -e 's/"zephyr"\|"nexus"\|"forge"\|"sentry"/"WORKER_X"/g' \
        -e 's/j_kro@[a-zA-Z0-9-]*/USERNAME@HOST/g' \
        '{}' \;
    
    # Remove backup files created by sed
    find "$TEMP_SANITIZED" -name "*.bak" -delete
    
    # Copy sanitized content to public worktree
    rsync -av --delete "$TEMP_SANITIZED/" "$PUBLIC_WORKTREE/"
    
    # Copy other important files
    cp -f "$PRIVATE_REPO_ROOT/README.md" "$PUBLIC_WORKTREE/" 2>/dev/null || true
    cp -f "$PRIVATE_REPO_ROOT/flake.nix" "$PUBLIC_WORKTREE/" 2>/dev/null || true
    cp -f "$PRIVATE_REPO_ROOT/LICENSE" "$PUBLIC_WORKTREE/" 2>/dev/null || true
    
    # Create public-friendly docs
    cat > "$PUBLIC_WORKTREE/USAGE_PUBLIC.md" << 'EOF'
# Public Usage Guide

This repository contains public infrastructure patterns extracted from a private deployment. To adapt for your use:

## Configuration Parameters

Replace these placeholders with your values:
- `192.168.100.X` → Your internal IP range
- `WALLET_PREFIX.NODE_NAME` → Your mining wallet IDs  
- `WORKER_X` → Your hostnames
- `USERNAME@HOST` → Your SSH usernames

## Example Adaptation

```nix
# In your private config
services.cluster-networking = {
  internalCIDR = "10.0.0.0/24";  # Replace 192.168.100.X
  nodes = {
    server1 = {
      ip = "10.0.0.10";
      hostname = "my-server";
    };
  };
};
```

See PARAMETERIZATION_BEST_PRACTICES.md for full documentation.
EOF
    
    # Clean up
    rm -rf "$TEMP_SANITIZED"
}

commit_and_push() {
    echo "Committing and pushing to public mirror..."
    
    # Add all files in public worktree
    (cd "$PUBLIC_WORKTREE" && git add .)
    
    # Check if there are changes to commit
    if [ -n "$(cd "$PUBLIC_WORKTREE" && git status --porcelain)" ]; then
        (cd "$PUBLIC_WORKTREE" && git commit -m "Auto-sanitize: $(date -Iseconds)")
        (cd "$PUBLIC_WORKTREE" && git push origin main)
        echo "Public mirror updated successfully!"
    else
        echo "No changes to commit."
    fi
}

# Run the process
sanitize_and_copy
commit_and_push

echo "Public mirror generation complete!"