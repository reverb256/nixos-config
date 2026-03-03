# NUR Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate NUR (Nix User Repository) into NixOS configuration to provide access to 1000+ community-maintained Nix packages.

**Architecture:** Add NUR as a flake input following existing patterns (zen-browser, aagl, etc.), wire it through specialArgs, enable the NUR module, and validate package access.

**Tech Stack:** NixOS Flakes, Nix User Repository (NUR)

---

### Task 1: Add NUR input to flake.nix

**Files:**
- Modify: `/etc/nixos/flake.nix:23-26` (insert after aagl input)

**Step 1: Add NUR input definition**

Add the NUR input after the aagl input (around line 22):

```nix
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

This defines the NUR repository source and ensures it follows your nixpkgs version to prevent conflicts.

**Step 2: Verify the syntax**

Run: `nix flake show /etc/nixos`
Expected: Output showing flake outputs without syntax errors

**Step 3: Commit**

```bash
git add flake.nix
git commit -m "feat(nur): add NUR input to flake

- Add github:nix-community/NUR as flake input
- Configure nixpkgs.follows for dependency consistency
Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Add nur to outputs parameters

**Files:**
- Modify: `/etc/nixos/flake.nix:40` (outputs function signature)

**Step 1: Update outputs function to include nur**

Change line 40 from:
```nix
  outputs = { self, nixpkgs, home-manager, zen-browser, firefox-addons, aagl, claude-native, nixpkgs-xr, scopebuddy, nixcord }:
```

To:
```nix
  outputs = { self, nixpkgs, home-manager, zen-browser, firefox-addons, aagl, claude-native, nixpkgs-xr, scopebuddy, nixcord, nur }:
```

This makes the nur input available within the outputs function.

**Step 2: Verify the syntax**

Run: `nix flake show /etc/nixos`
Expected: Output showing flake outputs without syntax errors

**Step 3: Commit**

```bash
git add flake.nix
git commit -m "feat(nur): add nur to outputs parameters

- Include nur in outputs function signature
- Makes nur input available for use in configuration
Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Add nur to specialArgs

**Files:**
- Modify: `/etc/nixos/flake.nix:50` (specialArgs.inputs.inherit)

**Step 1: Add nur to inherited inputs**

Change line 50 from:
```nix
            inherit nixpkgs home-manager zen-browser firefox-addons aagl claude-native nixpkgs-xr scopebuddy nixcord self;
```

To:
```nix
            inherit nixpkgs home-manager zen-browser firefox-addons aagl claude-native nixpkgs-xr scopebuddy nixcord nur self;
```

This passes nur through specialArgs so it's available in all modules.

**Step 2: Verify the syntax**

Run: `nix flake show /etc/nixos`
Expected: Output showing flake outputs without syntax errors

**Step 3: Commit**

```bash
git add flake.nix
git commit -m "feat(nur): add nur to specialArgs

- Pass nur input through specialArgs
- Makes nur available in all NixOS modules
Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Enable NUR module

**Files:**
- Modify: `/etc/nixos/flake.nix:53-58` (modules list)

**Step 1: Add NUR module to modules list**

Change line 53-58 from:
```nix
        modules = [
          ./hosts/zephyr/configuration.nix
          home-manager.nixosModules.home-manager
          aagl.nixosModules.default
          {nixpkgs.overlays = [ self.overlays.default ];}
        ];
```

To:
```nix
        modules = [
          ./hosts/zephyr/configuration.nix
          home-manager.nixosModules.home-manager
          aagl.nixosModules.default
          nur.nixosModules.nur
          {nixpkgs.overlays = [ self.overlays.default ];}
        ];
```

This enables the NUR module which sets up the NUR repository in your system.

**Step 2: Verify the syntax**

Run: `nix flake show /etc/nixos`
Expected: Output showing flake outputs without syntax errors

**Step 3: Commit**

```bash
git add flake.nix
git commit -m "feat(nur): enable NUR module

- Add nur.nixosModules.nur to modules list
- Enables NUR repository access in NixOS configuration
Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 5: Update flake lock

**Files:**
- Modify: `/etc/nixos/flake.lock` (auto-generated)

**Step 1: Update flake lock to fetch NUR**

Run: `nix flake update /etc/nixos`
Expected: Output showing NUR being fetched and flake.lock being updated

This downloads the NUR input and updates the lock file with the exact revision.

**Step 2: Verify NUR is in lock file**

Run: `grep -A 5 '"nur"' /etc/nixos/flake.lock`
Expected: Output showing nur node in flake.lock

**Step 3: Commit**

```bash
git add flake.lock
git commit -m "chore(nur): update flake lock with NUR

- Fetch and pin NUR repository revision
Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 6: Test build with NUR

**Files:**
- No file modifications (validation step)

**Step 1: Dry-run build to test NUR integration**

Run: `sudo nixos-rebuild build --flake /etc/nixos#zephyr`
Expected: Build completes successfully without errors
Note: This may take longer as it evaluates NUR repos

This validates that NUR integrates correctly with your configuration.

**Step 2: Check for NUR-related warnings**

Run: `sudo nixos-rebuild build --flake /etc/nixos#zephyr 2>&1 | grep -i nur`
Expected: Either no output or info messages (no errors)

**Step 3: Document success**

If build succeeds, the integration is working. No commit needed for this step.

---

### Task 7: Verify NUR package access

**Files:**
- Create: `/tmp/test-nur.nix` (temporary test file)

**Step 1: Create test package file**

Create `/tmp/test-nur.nix`:
```nix
{ pkgs, inputs, ... }: {
  environment.systemPackages = with pkgs;
    let
      # Test accessing a well-known NUR package
      nur-test = inputs.nur.repos.mic92.sops;
    in
    [
      nur-test
    ];
}
```

This tests that you can access NUR packages.

**Step 2: Test NUR package evaluation**

Run: `nix eval --raw /etc/nixos#zephyr.config.system.build.toplevel`
Expected: System config evaluates successfully

Alternative: Check if a NUR repo exists:
```bash
nix eval /etc/nixos#zephyr.inputs.nur.repos --apply 'x: builtins.attrNames x' | head -20
```
Expected: List of NUR repository names

**Step 3: Clean up test file**

Run: `rm /tmp/test-nur.nix`

**Step 4: Document verification**

No commit needed. Add a comment in your config documenting NUR usage.

---

### Task 8: Create usage documentation

**Files:**
- Create: `/etc/nixos/docs/nur-usage.md`

**Step 1: Create NUR usage guide**

Create `/etc/nixos/docs/nur-usage.md`:
```markdown
# NUR Usage Guide

NUR (Nix User Repository) is integrated into this NixOS configuration.

## What is NUR?

NUR is a community-driven repository of Nix packages not yet in nixpkgs.
Visit https://nur.nix-community.org/ to browse available packages.

## How to Use NUR Packages

### In Configuration Files

```nix
{ config, pkgs, inputs, ... }: {
  environment.systemPackages = with pkgs; [
    # Access NUR packages via inputs.nur.repos.<username>.<package>
    inputs.nur.repos.mic92.sops
  ];
}
```

### Example Packages

- `inputs.nur.repos.mic92.sops` - Secret management
- `inputs.nur.repos.iopq.spotify-adblock` - Spotify ad blocking
- `inputs.nur.repos.sternenseemann.texlive-small` - Minimal LaTeX

### Discovery

1. Visit https://nur.nix-community.org/
2. Search for packages
3. Find the repository username and package name
4. Add to your config using the pattern above

### Updating

Update NUR along with other flake inputs:
```bash
nix flake update /etc/nixos
```

## Notes

- NUR packages are built from source (no binary cache)
- Package quality varies - check repo maintenance status
- Some packages may have long build times
```

**Step 2: Commit documentation**

```bash
git add docs/nur-usage.md
git commit -m "docs(nur): add NUR usage guide

- Document how to discover and use NUR packages
- Include examples and common patterns
- Link to NUR website for package browsing
Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Summary

This plan integrates NUR into your NixOS configuration in 8 tasks:

1. ✅ Add NUR input definition
2. ✅ Wire through outputs parameters
3. ✅ Pass via specialArgs
4. ✅ Enable NUR module
5. ✅ Update flake lock
6. ✅ Test build
7. ✅ Verify package access
8. ✅ Document usage

**Total estimated time:** 20-30 minutes

**Success Criteria:**
- Flake builds successfully with NUR enabled
- Can access `inputs.nur.repos` in configuration
- NUR packages can be added to system
- Documentation is available for future reference

---

## References

- Design document: `docs/plans/2026-03-02-nur-integration-design.md`
- NUR website: https://nur.nix-community.org/
- NUR GitHub: https://github.com/nix-community/NUR
