#!/usr/bin/env bash
# Branch Cleanup Script for Reverb-OS Repository
# Generated: $(date)
#
# This script safely cleans up obsolete branches in the Reverb-OS NixOS configuration
# repository. It identifies and removes branches that are superseded, merged, or obsolete
# while preserving important development and production branches.

echo "==========================================="
echo "Reverb-OS Branch Cleanup Script"
echo "==========================================="
echo ""
echo "WARNING: This script will delete the following local branches:"
echo "- feature/ (appears superseded)"
echo "- feature/-fixed (appears superseded)"
echo "- wayland-plasma-cleanup (appears completed)"
echo "- refactor/layer-separation (appears completed)"
echo "- staging (older development branch)"
echo ""
echo "It will NOT touch these important branches:"
echo "- security-hardening-2026-02-03 (your current work)"
echo "- master (main development)"
echo "- infra (production deployment)"
echo ""
echo "IMPORTANT: Your current branch status:"
git branch -a
echo ""

read -p "Do you want to proceed with branch cleanup? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo "Proceeding with branch cleanup..."

# 1. First, sync with remote to get latest state
echo ""
echo "1. Fetching latest remote state..."
git fetch --all

# 2. Delete superseded local feature branches
echo ""
echo "2. Deleting superseded local branches..."

# Safely delete feature branches that appear superseded
BRANCHES_TO_DELETE=(
    "feature/"
    "feature/-fixed"
    "wayland-plasma-cleanup"
    "refactor/layer-separation"
    "staging"
)

for branch in "${BRANCHES_TO_DELETE[@]}"; do
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        echo "Deleting local branch: $branch"
        git branch -d "$branch" 2>/dev/null || echo "  - Branch $branch not fully merged, using force delete" && git branch -D "$branch"
    else
        echo "Branch $branch does not exist locally, skipping"
    fi
done

# 3. Check for remote branches that are deleted upstream
echo ""
echo "3. Cleaning up stale remote-tracking branches..."
git remote prune origin

# 4. Check if main branch should be synced with infra
echo ""
echo "4. Checking branch synchronization..."
echo "Current state:"
echo "Local master: $(git rev-parse --short master 2>/dev/null || echo "doesn't exist")"
echo "Local infra: $(git rev-parse --short infra 2>/dev/null || echo "doesn't exist")"
echo "Remote main: $(git rev-parse --short origin/main)"
echo "Remote infra: $(git rev-parse --short origin/infra)"

# Check if origin/main is behind origin/infra (which was the case we found earlier)
MAIN_COMMIT_COUNT=$(git rev-list --count origin/main 2>/dev/null || echo 0)
INFRA_COMMIT_COUNT=$(git rev-list --count origin/infra 2>/dev/null || echo 0)

if [ "$MAIN_COMMIT_COUNT" -lt "$INFRA_COMMIT_COUNT" ]; then
    echo ""
    echo "ALERT: origin/main is behind origin/infra!"
    echo "This means your GitHub Actions auto-merge main->infra won't work properly."
    echo "Recommendation: Sync main with infra to fix this."
    read -p "Do you want to sync origin/main with origin/infra? (yes/no): " -r SYNC_ANSWER
    echo
    
    if [[ $SYNC_ANSWER =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "WARNING: This will overwrite origin/main with origin/infra content!"
        read -p "Are you sure you want to proceed? This is irreversible! (I_UNDERSTAND): " -r CONFIRM_SYNC
        if [[ $CONFIRM_SYNC == "I_UNDERSTAND" ]]; then
            # Create a backup branch first
            BACKUP_NAME="backup-main-before-sync-$(date +%Y%m%d-%H%M%S)"
            echo "Creating backup branch: $BACKUP_NAME"
            git checkout master
            git pull origin master
            git checkout -b "$BACKUP_NAME"
            git push origin "$BACKUP_NAME"
            
            echo "Syncing origin/master with origin/infra..."
            git checkout master
            git reset --hard origin/infra
            git push origin master --force
            echo "Sync completed. origin/main now matches origin/infra"
        else
            echo "Sync cancelled."
        fi
    fi
else
    echo "Branches are in expected state (main not behind infra)"
fi

# 5. Final status
echo ""
echo "==========================================="
echo "CLEANUP COMPLETE"
echo "==========================================="
echo "Remaining local branches:"
git branch
echo ""
echo "All remote branches:"
git branch -r
echo ""
echo "Your current branch: $(git branch --show-current)"
echo ""
echo "Recommended next steps:"
echo "1. Continue your work on the security-hardening-2026-02-03 branch"
echo "2. Consider merging to master when ready for broader deployment"
echo "3. The GitOps workflow should now work properly if you synced branches"
echo "4. You may want to delete the temporary backup branch later if created"
echo ""

echo "Branch cleanup script finished!"