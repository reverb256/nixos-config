# Branch Cleanup and Backup Strategy

This document outlines the approach for cleaning up the branch complexity in the Reverb-OS repository.

## Current Situation

- Multiple feature branches with similar names ( variants)
- Inconsistent branch state (`main` behind `infra`)
- Unused/closed feature branches cluttering the repository
- Need to simplify for ongoing maintenance

## Branch Classification

### To Keep (Essential)
- `master` - Main development branch
- `infra` - Production deployment branch  
- `security-hardening-2026-02-03` - Current active work

### To Clean Up (Superseded/Obsolete)
- `feature/` - Superseded by newer versions
- `feature/-fixed` - Superseded by secure version
- `wayland-plasma-cleanup` - Appears completed
- `refactor/layer-separation` - Appears completed
- `staging` - Old development branch

## Cleanup Procedure

Use the `/etc/nixos/scripts/branch-cleanup.sh` script which:
1. Safely deletes obsolete local branches
2. Prunes stale remote references
3. Optionally fixes branch synchronization issues
4. Preserves all important work

## GitOps Workflow Fix

The script addresses the issue where `origin/main` was behind `origin/infra`, which breaks the GitHub Actions auto-merge workflow. After cleanup:
- GitHub Actions will properly validate `main` and merge to `infra`
- Deployment commands pulling from `main` will get the latest code
- Branch synchronization will work as designed

## Safety Measures

- Creates backup branches before destructive operations
- Asks for explicit confirmation before any changes
- Preserves all active work
- Maintains both `master` and `infra` branches

This cleanup will simplify ongoing development and fix the GitOps workflow issues.