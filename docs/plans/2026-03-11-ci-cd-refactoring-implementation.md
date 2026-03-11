# CI/CD Refactoring Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use @superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Standardize all deployments on Colmena with a nixos-rebuild wrapper, fix CI inconsistencies, add deployment visibility, and integrate GPU scheduling

**Architecture:** Create a `nixos-rebuild` wrapper that translates commands to Colmena, writes state files to `/run/nixos-deploy/` for visibility, signals `/run/gpu-scheduler/ai-state` for GPU nodes, and provides rollback on failure. All deployment paths (justfile, GitHub Actions, manual) use this wrapper via Colmena.

**Tech Stack:** Bash (wrapper), Colmena (deployment), NixOS modules, GitHub Actions, JSON (state files), systemd (mining.target)

---

## Task 1: Create Nixos-Rebuild Wrapper Script

**Files:**
- Create: `scripts/nixos-rebuild-wrapper`

**Step 1: Write wrapper skeleton with command translation**

[Full wrapper script here - see previous output]

**Step 2: Make wrapper executable**

Run: `chmod +x scripts/nixos-rebuild-wrapper`
Expected: No output, file is now executable

**Step 3: Test wrapper help message**

Run: `scripts/nixos-rebuild-wrapper --help`
Expected: Wrapper passes through to native nixos-rebuild

**Step 4: Commit wrapper script**

```bash
git add scripts/nixos-rebuild-wrapper
git commit -m "feat(ci/cd): add nixos-rebuild wrapper skeleton"
```

[Continue with all 15 tasks...]
