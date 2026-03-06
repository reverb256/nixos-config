# LM Studio Latest Version Installation Guide

## Problem Summary

**Current Issues:**
- ❌ Nix package `lmstudio-0.4.5-2` has **broken CLI** (`lms` segfaults)
- ❌ glibc compatibility issues with pre-built binaries
- ❌ Missing library symbols (`gnu_get_libc_version`, `backtrace`, etc.)

**Root Cause:**
The Nix package was built against an incompatible glibc version or has corrupted binaries.

---

## Solution: Manual Installation with Nix Integration

### Step 1: Download Latest Official Version

```bash
# Create installation directory
mkdir -p ~/.local/share/lm-studio
cd ~/.local/share/lm-studio

# Download latest from official website
# Visit https://lmstudio.ai/download in browser
# Or download AppImage directly (when URL is confirmed)
```

### Step 2: NixOS Wrapper (Recommended)

Create `/etc/nixos/modules/services/lm-studio-manual.nix`:

```nix
{ config, lib, pkgs, ... }:

{
  options.programs.lm-studio-manual = {
    enable = lib.mkEnableOption "Manual LM Studio installation";
    installPath = lib.mkOption {
      type = lib.types.path;
      default = "/home/j_kro/.local/share/lm-studio";
      description = "Path to manual LM Studio installation";
    };
  };

  config = lib.mkIf config.programs.lm-studio-manual.enable {
    environment.systemPackages = with pkgs; [
      # Wrapper for manually installed LM Studio
      (pkgs.writeShellScriptBin "lm-studio-manual" ''
        #!/bin/bash
        # Launcher for manually installed LM Studio
        cd ${config.programs.lm-studio-manual.installPath}
        exec ./LM-Studio "$@"
      '')
    ];

    # Allow unfree
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "lmstudio"
    ];
  };
}
```

### Step 3: Update NixOS Configuration

Add to `configuration.nix` or appropriate module:

```nix
programs.lm-studio-manual = {
  enable = true;
  installPath = "/home/j_kro/.local/share/lm-studio";
};
```

### Step 4: Rebuild

```bash
sudo nixos-rebuild switch --flake .#zephyr
```

---

## Alternative: Fix Nix Package by Rebuilding

### Check Package Definition

```bash
# View the current package definition
nix edit pkgs.lmstudio
# Or inspect it:
nix eval nixpkgs#lmstudio.meta
```

### Try Rebuilding with Updated Source

Create `/etc/nixos/overlay.nix` modification:

```nix
self: super: {
  lmstudio = super.lmstudio.overrideAttrs (oldAttrs: {
    # Force rebuild
    separateDebugInfo = true;
    # Or update version if newer is available
    version = "0.4.6";  # When available
    src = super.fetchurl {
      url = "https://installers.lmstudio.ai/linux/x64/0.4.6/LM-Studio-0.4.6-x64.AppImage";
      sha256 = "PREVIEW-SHA256";  # Get with nix-prefetch-url
    };
  });
}
```

---

## GPU Selection Without Broken CLI

### Option 1: Environment Variable (Works Now!) ⭐

```bash
# Stop LM Studio if running

# Start with 3090 only (GPU index 1)
CUDA_VISIBLE_DEVICES=1 lm-studio &

# Verify
nvidia-smi
# Should show only 3090 VRAM increasing when model loads
```

### Option 2: Update NixOS Service

Modify `/etc/nixos/modules/services/lm-studio-headless.nix`:

```nix
systemd.services.lm-studio-headless = {
  # ... existing config ...
  environment = {
    CUDA_VISIBLE_DEVICES = "1";  # 3090 only
  };
};
```

---

## Latest Version Tracking

### Check Current Version

1. Visit https://lmstudio.ai/download
2. Check version number in UI
3. Compare with `nixpkgs#lmstudio` version

### Update Strategy

**For Nix Package:**
```bash
# Update nixpkgs
nix flake update

# Check if newer version available
nix search nixpkgs lmstudio

# Rebuild
sudo nixos-rebuild switch --flake .#zephyr
```

**For Manual Install:**
```bash
# Download new AppImage
cd ~/.local/share/lm-studio
# Replace with new version from website

# No rebuild needed - just restart LM Studio
```

---

## Verification Commands

### Check Version
```bash
# If CLI works
lms --version

# From GUI
Help → About

# From package
nix eval nixpkgs#lmstudio.version
```

### Check GPU Usage
```bash
# Real-time monitoring
watch -n 1 nvidia-smi

# Check which GPU LM Studio uses
nvidia-smi --query-compute-apps=pid,used_memory --format=csv
```

### Test Model Loading
```bash
# Load model via API
curl -X POST http://127.0.0.1:1234/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"model-name","messages":[{"role":"user","content":"test"}]}'
```

---

## Benchmarking Workflow with GPU Selection

### Single GPU (3090 only)
```bash
# 1. Stop LM Studio
pkill -f lm-studio

# 2. Restart with 3090 only
CUDA_VISIBLE_DEVICES=1 lm-studio &

# 3. Load model in GUI
# 4. Run benchmark
python3 /tmp/benchmark_single_model.py <model-id>
```

### Multi-GPU (3090 + 3060 Ti)
```bash
# 1. Stop LM Studio
pkill -f lm-studio

# 2. Restart with both GPUs
lm-studio &  # No CUDA_VISIBLE_DEVICES

# 3. Load model in GUI
# 4. Run benchmark
python3 /tmp/benchmark_single_model.py <model-id>
```

---

## Next Steps

### Immediate (Today)
1. ✅ Use `CUDA_VISIBLE_DEVICES=1` for 3090-only testing
2. ✅ Run benchmarks on qwen3.5-27b next
3. ✅ Document results in `/tmp/model_speed_results.md`

### Short-term (This Week)
1. Download latest LM Studio from official website
2. Test if latest version has working CLI
3. Update NixOS configuration if needed
4. Document working version

### Long-term
1. Monitor nixpkgs for lmstudio updates
2. Submit bug report if issue persists
3. Consider contributing fix to nixpkgs

---

## Resources

- [LM Studio Official](https://lmstudio.ai/)
- [LM Studio Download](https://lmstudio.ai/download)
- [NixOS Package Search](https://search.nixos.org/packages?show=lmstudio)
- [Nixpkgs LM Studio PR/Issue Tracker](https://github.com/NixOS/nixpkgs/issues?q=lmstudio)
