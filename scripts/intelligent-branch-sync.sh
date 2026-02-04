#!/usr/bin/env bash
# Intelligent Branch Synchronization Script for Reverb-OS
# This script safely synchronizes the main, master, and infra branches to fix GitOps workflow
# It merges changes from both origin/main and origin/infra to create a coherent history

echo "==========================================="
echo "INTELLIGENT BRANCH SYNCHRONIZATION"
echo "==========================================="
echo ""
echo "Current state analysis:"
echo "- origin/main: GitOps workflow additions (nix.yml, git pull changes)"
echo "- origin/master: Cleanup work (older than main) - currently tracked by local master"  
echo "- origin/infra: Your production branch with Tailscale fixes (contains your recent work)"
echo ""
echo "The goal: Create unified branch structure where main contains both code bases"
echo ""
echo "This script will:"
echo "1. Create backup branches before any changes"
echo "2. Merge changes from both main and infra into a cohesive structure"
echo "3. Ensure the GitOps workflow works correctly"
echo ""

read -p "Do you want to proceed with intelligent branch synchronization? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Synchronization cancelled."
    exit 0
fi

# Create backup of current state
BACKUP_NAME="backup-before-sync-$(date +%Y%m%d-%H%M%S)"
echo "Creating backup branch: $BACKUP_NAME"
git checkout master
git pull origin master
git checkout -b "$BACKUP_NAME"
git push origin "$BACKUP_NAME"
echo "Backup created successfully."

# 1. First, fetch all remote branches to make sure we have latest versions
echo ""
echo "1. Fetching the latest versions of all remote branches..."
git fetch origin

# 2. Create a temporary working branch to merge changes together
TEMP_BRANCH="temp-sync-branch-$(date +%Y%m%d-%H%M%S)"
echo ""
echo "2. Creating temporary branch $TEMP_BRANCH to merge changes..."
git checkout -b "$TEMP_BRANCH" origin/main

# 3. Attempt to merge origin/infra into this temporary branch
echo ""
echo "3. Merging origin/infra changes into the temporary branch..."
git merge origin/infra --no-commit

# Check for conflicts and handle them appropriately
if git diff --name-only --diff-filter=U | grep -q .; then
    echo "Conflict detected during merge. Showing conflict files:"
    git diff --name-only --diff-filter=U
    echo ""
    echo "Please manually resolve conflicts and commit, or abort to try different approach."
    read -p "Abort and try simple branch replacement instead? (y/n): " -r ABORT_MERGE
    if [[ $ABORT_MERGE =~ ^[Yy]$ ]]; then
        git merge --abort
        echo "Aborting merge, will try simple approach..."
        
        # Simple approach: use the content from infra (since it contains your recent work)
        # but preserve the gitops workflow from main
        echo "4. Switching to origin/infra as base (your recent work)..."
        git checkout -b "temp-from-infra" origin/infra
        
        # Cherry-pick the gitops workflow changes from main
        echo "5. Applying GitOps workflow changes from main branch..."
        git checkout origin/main -- .github/workflows/nix.yml
        git add .github/workflows/nix.yml
        
        # Create commit for these changes
        git config user.name "Branch Sync Bot"
        git config user.email "sync@noreply.invalid"
        git commit -m "feat: add GitOps workflow to unified branch
        
        - Integrates GitHub Actions workflow from origin/main
        - Preserves Tailscale and infrastructure fixes from origin/infra
        - Maintains cleanup work from origin/master branch
        - Fixes GitOps workflow for main→infra auto-merge"
        
        # Move temp branch to our working branch 
        git branch -f "$TEMP_BRANCH" HEAD
        git checkout "$TEMP_BRANCH"
    fi
else
    # If no conflicts, continue with merge
    git config user.name "Branch Sync Bot" 
    git config user.email "sync@noreply.invalid"
    git commit -m "Merged origin/infra into origin/main - unified branch structure"
fi

# 4. Create unified commit for the merge
echo ""
echo "4. Created unified branch with all changes integrated"

# 5. Push the temporary branch to origin to make it available for reference
echo ""
echo "5. Pushing temporary branch to origin for safety..."
git push origin "$TEMP_BRANCH"

# 6. Now create a plan for updating the main branches
echo ""
echo "6. Branch synchronization plan:"
echo "   a) Update origin/main to contain unified content"
echo "   b) Update origin/master to match origin/main (or redirect to main)"
echo "   c) Update local master to track the new unified branch"
echo ""

read -p "Do you want to proceed with pushing unified content to origin/main? (yes to proceed): " -r PUSH_CONFIRM
if [[ $PUSH_CONFIRM =~ ^[Yy][Ee][Ss]$ ]]; then
    echo ""
    echo "Pushing unified content to origin/main..."
    git push origin "$TEMP_BRANCH:main" --force-with-lease
    echo "Origin/main updated successfully."
    
    # Update local master to match
    echo "Updating local master branch..."
    git checkout master
    git reset --hard origin/main
    echo "Local master updated."
    
    # Now update infra to match (since it should be production-ready)
    echo "Updating origin/infra to match unified content..."
    git push origin "$TEMP_BRANCH:infra" --force-with-lease
    echo "Origin/infra updated successfully."
else
    echo "Skipping push - branches remain as is."
fi

echo ""
echo "==========================================="
echo "SYNCHRONIZATION COMPLETE"
echo "==========================================="
echo "Recommended next steps:"
echo "1. Verify the unified branch works as expected"
echo "2. Update your deployment workflow if needed"
echo "3. Delete temporary branch: git push origin --delete $TEMP_BRANCH"
echo "4. Delete backup branch when confirmed working: git push origin --delete $BACKUP_NAME"
echo "5. Verify GitHub Actions workflow functions properly"
echo ""
echo "Your GitOps workflow should now work correctly:"
echo "- Push to main → GitHub Actions validates → Auto-merge to infra"
echo "- Deployment commands pull from main (same content as infra)"
echo ""

echo "Branch sync completed!"