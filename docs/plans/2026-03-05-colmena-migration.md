# Colmena Single-Source-of-Truth Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate /etc/nixos to single-source-of-truth Colmena architecture for centralized multi-host deployment

**Architecture:**
- flake.nix becomes single source of truth with commonModules array and mkNixosSystem helper
- colmena.nix adds deployment metadata using mkHost helper pattern
- Host configs simplified to only host-specific settings (no duplicate module imports)
- Deployment automation via justfile and colmena apply

**Tech Stack:** NixOS flakes, Colmena v0.5+, Agenix secrets, just deployment automation

---

## Task 1: Backup and Prepare Current Configuration

**Files:**
- Read: `/etc/nixos/flake.nix`
- Create: `/tmp/nixos-backup-$(date +%Y%m%d)/`

**Step 1: Create backup directory**

```bash
BACKUP_DIR="/tmp/nixos-backup-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"
cd /etc/nixos
```

Expected: Directory created, current directory is /etc/nixos

**Step 2: Backup current configuration**

```bash
git status --porcelain > "$BACKUP_DIR/git-status.txt"
git diff HEAD > "$BACKUP_DIR/current-changes.diff"
cp flake.nix "$BACKUP_DIR/flake.nix.backup"
```

Expected: Backup files created, no errors

**Step 3: Verify backup exists**

```bash
ls -la "$BACKUP_DIR"
cat "$BACKUP_DIR/git-status.txt"
```

Expected: List shows flake.nix.backup and current-changes.diff, git status shows uncommitted changes

**Step 4: Commit backup documentation**

```bash
git add -A
git commit -m "chore: backup before colmena migration

Backup location: $BACKUP_DIR
- flake.nix.backup: Original flake configuration
- current-changes.diff: Uncommitted changes
- git-status.txt: Current git state"
```

Expected: Commit created with backup info

---

## Task 2: Add Colmena Input to Flake

**Files:**
- Modify: `/etc/nixos/flake.nix:4-50`

**Step 1: Read current flake.nix inputs section**

```bash
head -50 /etc/nixos/flake.nix
```

Expected: Shows current inputs definition ending with agenix

**Step 2: Add colmena input after agenix**

Edit `/etc/nixos/flake.nix` and add colmena input in inputs section:

```nix
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Colmena - Multi-host deployment
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, spicetify-nix, zen-browser, firefox-addons, aagl, nur, claude-native, nixpkgs-xr, scopebuddy, nixcord, agenix, colmena }:
```

Change line 52 to include colmena in outputs function parameters.

**Step 3: Verify flake syntax**

```bash
cd /etc/nixos
nix flake check --no-build
```

Expected: No errors, flake evaluates successfully

**Step 4: Commit colmena input**

```bash
git add flake.nix
git commit -m "feat(colmena): add colmena input for multi-host deployment

- Add colmena flake input
- Include colmena in outputs parameters
- Prepares for colmena.nix integration"
```

Expected: Commit created

---

## Task 3: Refactor Flake - Create Common Modules Array

**Files:**
- Modify: `/etc/nixos/flake.nix:52-75`

**Step 1: Read current outputs section**

```bash
sed -n '52,75p' /etc/nixos/flake.nix
```

Expected: Shows current nixosConfigurations.zephyr definition

**Step 2: Replace outputs with commonModules pattern**

Edit `/etc/nixos/flake.nix` and replace the entire outputs block (lines 52-75) with:

```nix
  outputs = inputs @ { self, nixpkgs, home-manager, spicetify-nix, zen-browser, firefox-addons, aagl, nur, claude-native, nixpkgs-xr, scopebuddy, nixcord, agenix, colmena }:
    let
      # ========================================================================
      # COMMON MODULES - Shared across all hosts (single source of truth)
      # ========================================================================
      commonModules = [
        # External modules
        home-manager.nixosModules.home-manager
        aagl.nixosModules.default
        nur.modules.nixos.default
        agenix.nixosModules.default

        # Internal modules (auto-imports all subdirectories)
        ./modules/default.nix
      ];

      # ========================================================================
      # HELPER FUNCTION - Create NixOS system (eliminates duplication)
      # ========================================================================
      mkNixosSystem = { hostName, extraModules ? [] }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = commonModules ++ [
            ./hosts/${hostName}/configuration.nix
          ] ++ extraModules;
        };

      # ========================================================================
      # HOST DEFINITIONS - Single source of truth
      # ========================================================================
      hosts = {
        zephyr = { hostName = "zephyr"; };
        nexus = { hostName = "nexus"; };
        forge = { hostName = "forge"; };
        sentry = { hostName = "sentry"; };
      };

    in {
      # ========================================================================
      # OUTPUT 1: nixosConfigurations (for local nixos-rebuild)
      # ========================================================================
      nixosConfigurations = builtins.mapAttrs
        (name: value: mkNixosSystem { inherit (value) hostName; })
        hosts;

      # ========================================================================
      # OUTPUT 2: colmenaHive (for multi-host deployment)
      # ========================================================================
      colmenaHive = import ./colmena.nix {
        inherit inputs self;
        inherit hosts;
      };

      # ========================================================================
      # EXISTING OUTPUTS (maintain compatibility)
      # ========================================================================
      packages.x86_64-linux.claude = claude-native.packages.x86_64-linux.claude;

      overlays.default = import ./overlay.nix;

      apps.x86_64-linux.colmena = {
        type = "app";
        program = "${colmena.packages.x86_64-linux.colmena}/bin/colmena";
      };
    };
}
```

**Step 3: Verify flake evaluates**

```bash
cd /etc/nixos
nix flake check --no-build
nix eval .#nixosConfigurations.zephyr.config.system.build.toplevel --raw > /dev/null
echo "Exit code: $?"
```

Expected: "Exit code: 0", both commands succeed

**Step 4: Test existing zephyr config still builds**

```bash
sudo nixos-rebuild build --flake .#zephyr 2>&1 | tail -20
```

Expected: Build succeeds, no errors about missing modules

**Step 5: Commit refactored flake**

```bash
git add flake.nix
git commit -m "refactor(flake): convert to single-source-of-truth architecture

- Create commonModules array for shared imports
- Add mkNixosSystem helper to eliminate duplication
- Define hosts object as single source of truth
- Generate nixosConfigurations from hosts object
- Add colmenaHive output for multi-host deployment
- Maintain all existing outputs (packages, overlays, apps)"
```

Expected: Commit created

---

## Task 4: Create Colmena Configuration

**Files:**
- Create: `/etc/nixos/colmena.nix`

**Step 1: Create colmena.nix with deployment metadata**

```bash
cat > /etc/nixos/colmena.nix << 'EOF'
# Colmena Cluster Deployment Configuration
# Single-source-of-truth: Host definitions from flake.nix
{
  inputs,
  self,
  hosts,
  ...
}: let
  # ========================================================================
  # HELPER FUNCTION - Add deployment metadata to host config
  # ========================================================================
  mkHost = {
    hostName,
    targetHost,
  }: { ... }: {
    imports = [
      ./hosts/${hostName}/configuration.nix
    ];

    deployment = {
      inherit targetHost;
      targetUser = "j_kro";
      allowLocalDeployment = true;
    };
  };

  # ========================================================================
  # DEPLOYMENT METADATA - Target host addresses
  # Uses Tailscale DNS for reliable cluster connectivity
  # ========================================================================
  hostDeployment = {
    zephyr = { targetHost = "zephyr"; };
    nexus = { targetHost = "nexus"; };
    forge = { targetHost = "forge"; };
    sentry = { targetHost = "sentry"; };
  };

in {
  meta = {
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
    specialArgs = { inherit inputs self; };
  };

  # ========================================================================
  # GENERATE HOST CONFIGURATIONS
  # ========================================================================
  zephyr = mkHost {
    hostName = "zephyr";
    targetHost = hostDeployment.zephyr.targetHost;
  };

  nexus = mkHost {
    hostName = "nexus";
    targetHost = hostDeployment.nexus.targetHost;
  };

  forge = mkHost {
    hostName = "forge";
    targetHost = hostDeployment.forge.targetHost;
  };

  sentry = mkHost {
    hostName = "sentry";
    targetHost = hostDeployment.sentry.targetHost;
  };
}
EOF
```

Expected: File created successfully

**Step 2: Verify colmena.nix syntax**

```bash
cd /etc/nixos
nix flake check --no-build
```

Expected: No errors

**Step 3: Test colmena can evaluate configurations**

```bash
nix run .#apps.x86_64-linux.colmena -- eval --on zephyr 2>&1 | head -20
```

Expected: Shows evaluated configuration for zephyr, no errors

**Step 4: Commit colmena configuration**

```bash
git add colmena.nix
git commit -m "feat(colmena): add colmena deployment configuration

- Create colmena.nix with mkHost helper pattern
- Define deployment metadata for all 4 hosts
- Use Tailscale DNS for host addresses
- Allow local deployment for testing
- Configurations sourced from flake.nix hosts object"
```

Expected: Commit created

---

## Task 5: Create Deployment Automation (Justfile)

**Files:**
- Create: `/etc/nixos/justfile`

**Step 1: Create justfile with deployment commands**

```bash
cat > /etc/nixos/justfile << 'EOF'
# NixOS Cluster Deployment - Single-Source-of-Truth Colmena
# All deployment managed centrally from zephyr

export NIX_SHOW_STATS := "0"
FLAKE_PATH := "/etc/nixos"

_default:
    @just --list

# ============================================================================
# CRITICAL: Pre-deployment verification
# ============================================================================
verify-db:
    @echo "Checking distributed builds..."
    @sudo nix-show-config 2>/dev/null | grep -A 10 "builders" || echo "No builders configured"

# ============================================================================
# DEPLOYMENT COMMANDS
# ============================================================================
# Deploy to all hosts via colmena
deploy:
    just verify-db
    @echo "Deploying to all hosts..."
    cd {{FLAKE_PATH}} && sudo -E nix run .#apps.x86_64-linux.colmena -- apply --on @all --keep-result

# Deploy to specific host
zephyr:
    @echo "Deploying to zephyr..."
    cd {{FLAKE_PATH}} && sudo -E nix run .#apps.x86_64-linux.colmena -- apply --on zephyr

nexus:
    @echo "Deploying to nexus..."
    cd {{FLAKE_PATH}} && sudo -E nix run .#apps.x86_64-linux.colmena -- apply --on nexus

forge:
    @echo "Deploying to forge..."
    cd {{FLAKE_PATH}} && sudo -E nix run .#apps.x86_64-linux.colmena -- apply --on forge

sentry:
    @echo "Deploying to sentry..."
    cd {{FLAKE_PATH}} && sudo -E nix run .#apps.x86_64-linux.colmena -- apply --on sentry

# ============================================================================
# LOCAL OPERATIONS (no colmena)
# ============================================================================
# Local switch (current host only)
switch:
    @echo "Switching local system..."
    cd /etc/nixos && sudo nixos-rebuild switch --flake ".#$(hostname -s)"

# Test configuration (dry run)
test:
    @echo "Testing configuration..."
    cd {{FLAKE_PATH}} && nix flake check
    @echo "Building all hosts (dry run)..."
    cd {{FLAKE_PATH}} && sudo -E nix run .#apps.x86_64-linux.colmena -- build

# ============================================================================
# UTILITIES
# ============================================================================
# Show git status on all nodes
status:
    @echo "Git status on all nodes..."
    @echo "=== ZEPHYR (local) ==="
    @cd {{FLAKE_PATH}} && git log -1 --oneline
    @for host in nexus forge sentry; do \
        echo "=== $$host ==="; \
        ssh $$host "cd /etc/nixos && git log -1 --oneline" 2>/dev/null || echo "  unreachable"; \
    done

# Sync all repos to current branch
sync:
    @echo "Syncing all nodes to $(git branch --show-current)..."
    @for host in nexus forge sentry; do \
        echo "Syncing $$host..."; \
        ssh $$host "cd /etc/nixos && git fetch origin && git reset --hard origin/$(git branch --show-current)" 2>/dev/null || true; \
    done

# Show cluster status
cluster-status:
    @echo "Cluster Status:"
    @for host in zephyr nexus forge sentry; do \
        echo -n "$$host: "; \
        if [ "$$host" = "$(hostname -s)" ]; then \
            echo "local"; \
        else \
            ssh -o ConnectTimeout=2 $$host "echo OK" 2>/dev/null && echo "up" || echo "down"; \
        fi; \
    done
EOF
```

Expected: File created successfully

**Step 2: Install just if not present**

```bash
which just || nix-env -iA nixpkgs.just
```

Expected: just command now available

**Step 3: Test justfile recipes**

```bash
cd /etc/nixos
just --list
just cluster-status
```

Expected: Lists all recipes, shows cluster status

**Step 4: Commit deployment automation**

```bash
git add justfile
git commit -m "feat(deploy): add justfile deployment automation

- Add justfile with colmena deployment commands
- Support per-host deployment (zephyr, nexus, forge, sentry)
- Add cluster status and sync utilities
- Add test command for dry-run builds"
```

Expected: Commit created

---

## Task 6: Migrate Remote Host Configurations

**Files:**
- Create: `/etc/nixos/hosts/nexus/configuration.nix`
- Create: `/etc/nixos/hosts/forge/configuration.nix`
- Create: `/etc/nixos/hosts/sentry/configuration.nix`

**Step 1: Fetch nexus configuration**

```bash
ssh nexus "cat /etc/nixos/configuration.nix" > /etc/nixos/hosts/nexus/configuration.nix
```

Expected: File created, check size: `ls -la /etc/nixos/hosts/nexus/configuration.nix`

**Step 2: Fetch forge configuration**

```bash
ssh forge "cat /etc/nixos/configuration.nix" > /etc/nixos/hosts/forge/configuration.nix
```

Expected: File created, check size: `ls -la /etc/nixos/hosts/forge/configuration.nix`

**Step 3: Fetch sentry configuration**

```bash
ssh sentry "cat /etc/nixos/configuration.nix" > /etc/nixos/hosts/sentry/configuration.nix
```

Expected: File created, check size: `ls -la /etc/nixos/hosts/sentry/configuration.nix`

**Step 4: Copy hardware configs from remotes**

```bash
scp nexus:/etc/nixos/hardware-configuration.nix /etc/nixos/hosts/nexus/
scp forge:/etc/nixos/hardware-configuration.nix /etc/nixos/hosts/forge/
scp sentry:/etc/nixos/hardware-configuration.nix /etc/nixos/hosts/sentry/
```

Expected: All 3 hardware configs copied

**Step 5: Verify configs evaluate**

```bash
cd /etc/nixos
nix eval .#nixosConfigurations.nexus.config.system.build.toplevel --raw > /dev/null && echo "nexus: OK"
nix eval .#nixosConfigurations.forge.config.system.build.toplevel --raw > /dev/null && echo "forge: OK"
nix eval .#nixosConfigurations.sentry.config.system.build.toplevel --raw > /dev/null && echo "sentry: OK"
```

Expected: All three hosts show "OK"

**Step 6: Commit remote host configurations**

```bash
git add hosts/nexus/ hosts/forge/ hosts/sentry/
git commit -m "feat(hosts): add remote host configurations

- Migrate nexus config from remote via SSH
- Migrate forge config from remote via SSH
- Migrate sentry config from remote via SSH
- Include hardware-configuration.nix for each host
- All hosts evaluate successfully"
```

Expected: Commit created

---

## Task 7: Simplify Zephyr Configuration (Remove Duplicates)

**Files:**
- Modify: `/etc/nixos/hosts/zephyr/configuration.nix:9-45`

**Step 1: Identify duplicate module imports in zephyr config**

```bash
grep -n "^\s*../../modules/" /etc/nixos/hosts/zephyr/configuration.nix | head -20
```

Expected: Shows many ../../modules/ imports that are now in modules/default.nix

**Step 2: Remove duplicate imports, keep only essential ones**

Edit `/etc/nixos/hosts/zephyr/configuration.nix` and simplify the imports section to:

```nix
{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    # ========================================================================
    # BASE MODULES
    # ========================================================================

    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # All other modules auto-imported via ../../modules/default.nix
    # This includes: system, desktop, shell, gaming, development, services
    ../../modules/default.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking.hostName = "zephyr";

  # ... rest of host-specific settings ...
```

**Step 3: Verify zephyr still builds**

```bash
cd /etc/nixos
sudo nixos-rebuild build --flake .#zephyr 2>&1 | tail -30
```

Expected: Build succeeds, no module-not-found errors

**Step 4: Test colmena evaluation for zephyr**

```bash
nix run .#apps.x86_64-linux.colmena -- eval --on zephyr 2>&1 | head -30
```

Expected: Shows evaluated config, no import errors

**Step 5: Commit zephyr simplification**

```bash
git add hosts/zephyr/configuration.nix
git commit -m "refactor(zephyr): remove duplicate module imports

- Remove ../../modules/ imports (now in modules/default.nix)
- Keep only hardware-configuration.nix and modules/default.nix
- All host-specific settings preserved
- Configuration evaluates successfully"
```

Expected: Commit created

---

## Task 8: Test Colmena Build (Dry Run)

**Files:**
- Test: colmena build command

**Step 1: Build all host configurations**

```bash
cd /etc/nixos
sudo -E nix run .#apps.x86_64-linux.colmena -- build 2>&1 | tee /tmp/colmena-build.log
```

Expected: Builds all hosts, may take 5-10 minutes, check exit code

**Step 2: Check build results**

```bash
echo "Exit code: $?"
tail -50 /tmp/colmena-build.log
```

Expected: Exit code 0, no errors in log

**Step 3: Verify each host built successfully**

```bash
grep -E "(zephyr|nexus|forge|sentry)" /tmp/colmena-build.log | grep -E "(Building| succeeded)"
```

Expected: Shows all 4 hosts built successfully

**Step 4: Document successful test**

```bash
echo "Colmena build test completed successfully: $(date)" > /tmp/colmena-test-success.txt
cat /tmp/colmena-test-success.txt
```

Expected: Confirmation message

**Step 5: No commit needed (test only)**

Expected: Nothing to commit

---

## Task 9: First Colmena Deployment (Zephyr Only)

**Files:**
- Test: colmena apply to zephyr

**Step 1: Pre-deployment checklist**

```bash
just cluster-status
just test
```

Expected: All hosts up, test passes

**Step 2: Deploy to zephyr (local deployment)**

```bash
cd /etc/nixos
just zephyr 2>&1 | tee /tmp/colmena-zephyr-deploy.log
```

Expected: Deployment succeeds, system switches to new generation

**Step 3: Verify zephyr post-deployment**

```bash
sudo nixos-rebuild list-generations | head -5
systemctl is-active ai-inference-gateway
systemctl is-active spacebot
```

Expected: Shows new generation, services active

**Step 4: Check for errors in deployment log**

```bash
grep -i "error\|warning\|failed" /tmp/colmena-zephyr-deploy.log | head -20
```

Expected: No critical errors (warnings OK)

**Step 5: Commit post-deployment verification**

```bash
echo "Colmena deployment to zephyr successful: $(date)" > /tmp/zephyr-deploy-success.txt
git add .
git commit -m "test(colmena): verify zephyr deployment successful

- Deployed to zephyr via colmena apply
- All services active (ai-inference, spacebot)
- New generation active
- No critical errors"
```

Expected: Commit created

---

## Task 10: Deploy to All Remote Hosts

**Files:**
- Test: parallel colmena deployment

**Step 1: Sync git repos on all remote hosts**

```bash
just sync
just status
```

Expected: All nodes show same commit

**Step 2: Pre-deployment verification**

```bash
just test
just cluster-status
```

Expected: All hosts up, test passes

**Step 3: Deploy to all hosts in parallel**

```bash
just deploy 2>&1 | tee /tmp/colmena-all-deploy.log
```

Expected: Deployment to all hosts, may take 15-30 minutes

**Step 4: Verify deployment success**

```bash
echo "Exit code: $?"
tail -50 /tmp/colmena-all-deploy.log
grep "succeeded" /tmp/colmena-all-deploy.log | wc -l
```

Expected: Exit code 0, shows 4 hosts succeeded

**Step 5: Post-deployment validation**

```bash
for host in zephyr nexus forge sentry; do
    echo "=== $host ==="
    ssh $host "hostname && systemctl is-active sshd tailscaled" 2>/dev/null || echo "$host: unreachable"
done
```

Expected: All hosts respond with hostname and active services

**Step 6: Commit successful deployment**

```bash
git add .
git commit -m "deploy(colmena): successful multi-host deployment

- Deployed to all 4 hosts via colmena
- All hosts responsive and services active
- Single-source-of-truth architecture operational
- Deployment automation verified"
```

Expected: Commit created

---

## Task 11: Final Verification and Documentation

**Files:**
- Create: `/etc/nixos/docs/COLMENA_DEPLOYMENT.md`
- Create: `/etc/nixos/docs/MIGRATION_SUMMARY.md`

**Step 1: Create deployment documentation**

```bash
mkdir -p /etc/nixos/docs
cat > /etc/nixos/docs/COLMENA_DEPLOYMENT.md << 'EOF'
# Colmena Multi-Host Deployment Guide

## Quick Start

```bash
# Deploy to all hosts
just deploy

# Deploy to specific host
just zephyr  # or nexus, forge, sentry

# Test configuration (dry run)
just test

# Check cluster status
just cluster-status
```

## Architecture

- **Single Source of Truth**: flake.nix defines all hosts
- **Common Modules**: Shared across all hosts via commonModules array
- **Deployment Metadata**: colmena.nix adds targetHost configuration
- **Helper Functions**: mkNixosSystem and mkHost eliminate duplication

## Host Addresses

Uses Tailscale DNS for reliable connectivity:
- zephyr: 100.81.182.5
- nexus: 100.86.158.18
- forge: 100.95.222.45
- sentry: 100.82.210.39

## Adding a New Host

1. Create host config: `hosts/newhost/configuration.nix`
2. Add to flake.nix hosts object: `newhost = { hostName = "newhost"; };`
3. Add to colmena.nix hostDeployment: `newhost = { targetHost = "newhost"; };`
4. Add to colmena.nix hosts: `newhost = mkHost { inherit (hostDeployment.newhost) hostName targetHost; };`

## Troubleshooting

```bash
# Check distributed builds
just verify-db

# Rollback specific host
nixos-rebuild switch --rollback

# View deployment logs
journalctl -u nixos-rebuild
```
EOF
```

Expected: Documentation created

**Step 2: Create migration summary**

```bash
cat > /etc/nixos/docs/MIGRATION_SUMMARY.md << 'EOF'
# Colmena Migration Summary

## Completed

- ✅ Refactored flake.nix to single-source-of-truth
- ✅ Added colmena input and colmenaHive output
- ✅ Created colmena.nix deployment configuration
- ✅ Added justfile deployment automation
- ✅ Migrated remote host configurations
- ✅ Simplified zephyr configuration
- ✅ Deployed successfully to all 4 hosts

## Architecture Changes

### Before
- Separate nixosConfigurations (duplication)
- No colmena support
- Manual SSH deployment

### After
- Single hosts object in flake.nix
- colmenaHive for multi-host deployment
- Automated deployment via justfile
- Helper functions eliminate duplication

## Benefits

1. **Single Source of Truth**: Hosts defined once
2. **Zero Duplication**: Helper functions reduce repetition
3. **Automated Deployment**: `just deploy` updates all hosts
4. **Easy Maintenance**: Add new host in 4 lines of code
5. **Backward Compatible**: nixos-rebuild still works

## Migration Date

$(date)

## Verified By

Colmena deployment test: All hosts operational
EOF
```

Expected: Migration summary created

**Step 3: Create final verification script**

```bash
cat > /etc/nixos/scripts/verify-colmena-setup.sh << 'EOF'
#!/usr/bin/env bash
# Verify Colmena setup is working correctly

set -e

echo "Verifying Colmena setup..."
echo ""

# Check 1: Flake evaluates
echo "1. Checking flake evaluation..."
cd /etc/nixos
nix flake check --no-build > /dev/null 2>&1
echo "   ✓ Flake evaluates"

# Check 2: All host configs evaluate
echo "2. Checking host configurations..."
for host in zephyr nexus forge sentry; do
    nix eval .#nixosConfigurations.$host.config.system.build.toplevel --raw > /dev/null 2>&1
    echo "   ✓ $host configuration evaluates"
done

# Check 3: Colmena can access all hosts
echo "3. Checking host connectivity..."
for host in nexus forge sentry; do
    if ssh -o ConnectTimeout=2 $host "hostname" > /dev/null 2>&1; then
        echo "   ✓ $host reachable"
    else
        echo "   ✗ $host unreachable"
    fi
done

# Check 4: Deployment automation available
echo "4. Checking deployment automation..."
if command -v just > /dev/null 2>&1; then
    echo "   ✓ just command available"
    just --list > /dev/null 2>&1
    echo "   ✓ justfile recipes defined"
else
    echo "   ✗ just command not found"
fi

echo ""
echo "Verification complete!"
EOF

chmod +x /etc/nixos/scripts/verify-colmena-setup.sh
```

Expected: Verification script created and made executable

**Step 4: Run final verification**

```bash
/etc/nixos/scripts/verify-colmena-setup.sh
```

Expected: All checks pass

**Step 5: Commit documentation and verification**

```bash
git add docs/ scripts/verify-colmena-setup.sh
git commit -m "docs(colmena): add deployment guide and migration summary

- Add COLMENA_DEPLOYMENT.md with quick start guide
- Add MIGRATION_SUMMARY.md documenting changes
- Add verify-colmena-setup.sh verification script
- Document architecture changes and benefits"
```

Expected: Final commit created

---

## Task 12: Tag Migration Complete

**Files:**
- Git tag

**Step 1: Create migration complete tag**

```bash
git tag -a colmena-migration-complete -m "Colmena Single-Source-of-Truth Migration Complete

Migration from simple flake to Colmena multi-host deployment:
- Single source of truth in flake.nix
- Automated deployment via colmena
- All 4 hosts successfully deployed
- Migration verified and documented

Date: $(date)
"
```

Expected: Tag created

**Step 2: Show final git log**

```bash
git log --oneline -10
git tag -l
```

Expected: Shows migration commits and new tag

**Step 3: Optional: Push to remote**

```bash
# Uncomment when ready to push
# git push origin main
# git push origin colmena-migration-complete
```

Expected: If executed, pushes to remote (commented for safety)

**Step 4: Migration complete summary**

```bash
cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║     COLMENA MIGRATION COMPLETE                             ║
╠════════════════════════════════════════════════════════════╣
║                                                              ║
║  ✓ Single source of truth established                        ║
║  ✓ Colmena deployment operational                            ║
║  ✓ All 4 hosts deployed successfully                         ║
║  ✓ Documentation complete                                    ║
║                                                              ║
║  Next steps:                                                 ║
║  - Use 'just deploy' for multi-host deployment              ║
║  - Use 'just test' for dry-run builds                        ║
║  - Use 'just status' to check all hosts                     ║
║                                                              ║
╚════════════════════════════════════════════════════════════╝
EOF
```

Expected: Success message displayed

**Step 5: Final commit for tag**

```bash
git add .
git commit --allow-empty -m "tag: colmena migration complete

- All migration tasks completed successfully
- Single-source-of-truth architecture operational
- Tagged as colmena-migration-complete"
```

Expected: Final commit created

---

## Testing Checklist

After completing all tasks, verify:

- [ ] `nix flake check` passes with no errors
- [ ] `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel` works for all hosts
- [ ] `just test` completes successfully
- [ ] `just cluster-status` shows all hosts up
- [ ] `just deploy` successfully deploys to all hosts
- [ ] All services active on each host
- [ ] Documentation is complete and accurate
- [ ] Verification script passes all checks

## Rollback Procedure

If migration fails at any point:

```bash
# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Or checkout specific commit
git log --oneline
git checkout <commit-hash>
sudo nixos-rebuild switch --flake .#zephyr
```

## Success Criteria

Migration is complete when:
1. ✅ All 12 tasks completed without errors
2. ✅ All hosts deployed via colmena successfully
3. ✅ Deployment automation verified
4. ✅ Documentation complete
5. ✅ Verification script passes
6. ✅ Tag created at colmena-migration-complete
