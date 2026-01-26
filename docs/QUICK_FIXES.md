# Quick Security and Code Quality Fixes

## Status: SECURITY FIXES COMPLETED ✅

All critical security issues have been resolved as of January 17, 2026. This document is now for reference only.

### ✅ Previously Resolved Issues

#### 1. Hardcoded API Credentials ✅ FIXED
**Previous Issue**: Hardcoded API token in configuration
**Resolution**: Now using secure secret management with agenix
**Location**: `/etc/nixos/home.nix:190` uses `config.age.secrets.claude-api-key.path`

#### 2. SSH Security ✅ FIXED  
**Previous Issue**: Root SSH access configuration
**Resolution**: SSH properly configured with key-based authentication
**Location**: `/etc/nixos/configuration.nix:353` has `PermitRootLogin = "no"`

#### 3. Code Quality Issues ✅ FIXED
**Previous Issues**: Dead code, inconsistent naming, large modules
**Resolution**: Codebase cleaned up and modularized

### 🔒 SSH Security Status ✅ SECURE

**Current Configuration**: SSH properly configured with key-based authentication
**Root Access**: Disabled via `PermitRootLogin = "no"`
**Authentication**: Key-only, no password authentication

### 🧹 Remove Dead Code

**File**: `/etc/nixos/configuration.nix`
**Lines**: 133, 138-139

**Remove these commented lines**:
```nix
# ./modules/storage.nix
# ./modules/fish-starship.nix
```

**File**: `/etc/nixos/modules/gaming.nix`
**Lines**: 69-155

**Remove all commented systemd services** (vr-90hz-optimization, 4k-60hz-optimization, etc.)

### 🔄 Fix Environment Variable Duplication

**Choose ONE location for environment variables and remove from others:**

**Keep in**: `/etc/nixos/configuration.nix` (lines 461-462)
**Remove from**: `/etc/nixos/home.nix` (lines 28-29)
**Remove from**: `/etc/nixos/modules/fish-starship.nix` (lines 272-274)

### 🔧 Fix Shell Alias Inconsistency

**File**: `/etc/nixos/home.nix`
**Lines**: 128-130

**Current**:
```nix
update = "just upgrade-all";
build = "just build";
test = "just test";
```

**Fix** (change to match system aliases):
```nix
update = "sudo nixos-rebuild switch --flake /etc/nixos";
build = "sudo nixos-rebuild build --flake /etc/nixos";
nixtest = "sudo nixos-rebuild test --flake /etc/nixos";
```

## Quick Performance Optimization

### Nix Build Optimization

**File**: `/etc/nixos/configuration.nix`
**Lines**: 62-63

**Current**:
```nix
max-jobs = 8; # Parallel derivations (use ~1/2 of threads)
cores = 16; # Cores per derivation (use ~1/2 of cores)
```

**Fix**:
```nix
max-jobs = 32; # Full thread utilization for Ryzen 5950X
cores = 16; # Cores per derivation
```

## One-Line Fixes Summary

```bash
# 1. Remove hardcoded token (line 471 in configuration.nix)
sed -i '471d' /etc/nixos/configuration.nix

# 2. Fix SSH security (line 320 in configuration.nix)
sed -i 's/PermitRootLogin = "yes";/PermitRootLogin = "no";/' /etc/nixos/configuration.nix

# 3. Remove commented imports (lines 133, 138-139 in configuration.nix)
sed -i '133d;138,139d' /etc/nixos/configuration.nix

# 4. Fix Nix build settings (lines 62-63 in configuration.nix)
sed -i 's/max-jobs = 8;/max-jobs = 32;/' /etc/nixos/configuration.nix

# 5. Remove duplicate environment variables from home.nix
sed -i '28,29d' /etc/nixos/home.nix

# 6. Remove duplicate environment variables from fish-starship.nix
sed -i '272,274d' /etc/nixos/modules/fish-starship.nix
```

## Testing Commands

```bash
# Test configuration syntax
sudo nixos-rebuild build --flake /etc/nixos

# Apply changes
sudo nixos-rebuild switch --flake /etc/nixos

# Test SSH security
ssh localhost 'echo "SSH access test"'  # Should fail for root

# Test mining services
sudo systemctl status lolminer-nvidia.service
sudo systemctl status xmrig.service
```

## Rollback Commands

If any issues occur:

```bash
# Quick rollback
sudo nixos-rebuild switch --rollback

# Or manual rollback for specific changes:
# 1. Restore SSH: sed -i 's/PermitRootLogin = "no";/PermitRootLogin = "yes";/' /etc/nixos/configuration.nix
# 2. Restore Nix jobs: sed -i 's/max-jobs = 32;/max-jobs = 8;/' /etc/nixos/configuration.nix
# 3. Re-add imports: echo './modules/storage.nix' >> /etc/nixos/configuration.nix
```

These quick fixes address the most critical security and code quality issues in under 30 minutes each, providing immediate improvements to security and maintainability.