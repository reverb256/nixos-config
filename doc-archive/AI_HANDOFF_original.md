#!/usr/bin/env bash
# NixOS Configuration - AI Hand-off Script
# Generated: $(date)
# Location: /data/@projects/infra/nixos/

set -euo pipefail

echo "=========================================="
echo "NixOS Configuration - AI Hand-off"
echo "=========================================="
echo ""

# ============================================================================
# PROJECT OVERVIEW
# ============================================================================

echo "📋 PROJECT OVERVIEW"
echo "-------------------"
echo "Repository: /data/@projects/infra/nixos/"
echo "Current Branch: $(git branch --show-current)"
echo "Worktree: Yes (separate from /etc/nixos)"
echo ""
echo "⚠️  CRITICAL: /etc/nixos must ALWAYS be on master branch"
echo "   This worktree is for development"
echo ""

# ============================================================================
# BRANCH STATUS
# ============================================================================

echo "🌿 BRANCH STATUS"
echo "----------------"
git branch -v
echo ""

# ============================================================================
# RECENT WORK SUMMARY
# ============================================================================

echo "🔧 RECENT WORK SUMMARY"
echo "----------------------"
echo ""
echo "COMPLETED:"
echo "  ✅ Fixed CUDA_PATH for LM Studio (changed to cuda_cudart)"
echo "  ✅ Added LD_LIBRARY_PATH for dynamically linked CUDA apps"
echo "  ✅ Added CUDA libraries to nix-ld for AppImage support"
echo "  ✅ Removed duplicate assertions across modules"
echo "  ✅ Fixed GSP firmware assertion for open/proprietary modules"
echo "  ✅ Switched all hosts to open-source NVIDIA kernel modules"
echo "  ✅ Harmonized NVIDIA beta drivers across all 4 hosts"
echo "  ✅ Implemented layer separation (system vs user packages)"
echo "  ✅ Fixed mining services (lolminer-nvidia nvidia-smi path)"
echo "  ✅ Optimized Nix build settings (max-jobs=4, cores=6)"
echo "  ✅ Configured distributed builds (4 machines, 78 cores total)"
echo "  ✅ Fixed SSH keys for distributed builds (using id_rsa)"
echo ""
echo "IN PROGRESS:"
echo "  🔄 System rebuild with distributed builds"
echo "     - Building: firefox-unwrapped-147.0.1 (for Zen Browser)"
echo "     - Building: python3.12-torch-2.9.1 (PyTorch with CUDA)"
echo "     - Status: Check with: tail -f /tmp/nix-build.log"
echo ""
echo "PENDING / KNOWN ISSUES:"
echo "  ⚠️  Zen Browser pinning lost - needs to be re-applied"
echo "      (commit 15ceb90 on refactor/layer-separation branch)"
echo "  ⚠️  PyTorch/TensorFlow building from source (not in cache)"
echo "  ⚠️  Build taking 1-2 hours due to large packages"
echo ""

# ============================================================================
# BRANCH STRATEGY
# ============================================================================

echo "🌳 BRANCH STRATEGY"
echo "------------------"
echo ""
echo "master (in /etc/nixos):"
echo "  - Production configuration"
echo "  - Always stable, working state"
echo "  - Currently has: distributed-builds SSH key fix"
echo ""
echo "refactor/layer-separation (this worktree):"
echo "  - Development branch"
echo "  - Contains: Zen Browser pinning, layer separation, mining fixes"
echo "  - Ahead of master by multiple commits"
echo "  - Should be merged to master when ready"
echo ""
echo "staging:"
echo "  - Currently on this branch"
echo "  - Behind master by 1 commit"
echo "  - Purpose unclear - may need cleanup"
echo ""

# ============================================================================
# SYSTEM ARCHITECTURE
# ============================================================================

echo "🏗️  SYSTEM ARCHITECTURE"
echo "----------------------"
echo ""
echo "Hosts (4 total):"
echo "  1. zephyr (main workstation) - 32 cores, RTX 3090"
echo "  2. nexus (backup server) - 24 cores, 2x RTX 3060 Ti"
echo "  3. forge (build worker) - 6 cores, 2x RTX 4060 + 2x RX 5700 XT"
echo "  4. sentry (monitoring) - 16 cores, RX 5600 XT"
echo ""
echo "Total Distributed Build Power: 78 cores"
echo ""
echo "Configuration Layers:"
echo "  Layer 0: Nix Store (/nix/store) - Immutable packages"
echo "  Layer 1: System (NixOS) - /etc/nixos/ - System-wide config"
echo "  Layer 2: User (Home Manager) - /etc/nixos/home.nix - User config"
echo "  Layer 3: Ephemeral (nix profile) - Should be empty"
echo ""

# ============================================================================
# KEY FILES AND MODULES
# ============================================================================

echo "📁 KEY FILES AND MODULES"
echo "------------------------"
echo ""
echo "Entry Points:"
echo "  - flake.nix                    # Main flake configuration"
echo "  - configuration.nix            # System entry point"
echo "  - home.nix                     # Home Manager configuration"
echo ""
echo "Important Modules:"
echo "  - modules/nvidia-wayland.nix   # NVIDIA + Wayland setup"
echo "  - modules/gaming.nix           # Gaming/VR configuration"
echo "  - modules/mining.nix           # Mining services (xmrig, lolminer)"
echo "  - modules/system-packages.nix  # System packages (now cleaned)"
echo "  - modules/nix-config.nix       # Nix settings, build config"
echo "  - modules/distributed-builds.nix # Distributed build configuration"
echo "  - modules/systemd-slices.nix   # Resource isolation"
echo ""
echo "Host Configs:"
echo "  - hosts/zephyr/configuration.nix"
echo "  - hosts/nexus/configuration.nix"
echo "  - hosts/forge/configuration.nix"
echo "  - hosts/sentry/configuration.nix"
echo ""

# ============================================================================
# CURRENT BUILD STATUS
# ============================================================================

echo "🔨 CURRENT BUILD STATUS"
echo "----------------------"
echo ""
if pgrep -x "nixos-rebuild" > /dev/null; then
    echo "✅ Build is RUNNING"
    echo ""
    echo "Monitor with:"
    echo "  tail -f /tmp/nix-build.log"
    echo ""
    echo "Active build processes:"
    ps aux | grep nixbld | grep -E "(rustc|cargo|clang|g\+\+)" | wc -l | xargs echo "  Compiler processes:"
    echo ""
    echo "Check distributed builds:"
    echo "  ps aux | grep 'ssh.*nix' | grep -v grep"
else
    echo "❌ Build is NOT running"
    echo ""
    echo "To restart:"
    echo "  just switch"
    echo "  # or"
    echo "  sudo nixos-rebuild switch --flake .#zephyr"
fi
echo ""

# ============================================================================
# DISTRIBUTED BUILDS
# ============================================================================

echo "🌐 DISTRIBUTED BUILDS"
echo "---------------------"
echo ""
echo "Status: CONFIGURED"
echo ""
echo "Build Machines:"
echo "  - localhost (zephyr): 8 jobs, speed=4, features=cuda"
echo "  - nexus (10.1.1.120): 6 jobs, speed=3, features=cuda"
echo "  - forge (10.1.1.130): 3 jobs, speed=1, features=cuda"
echo "  - sentry (10.1.1.140): 4 jobs, speed=2, features=kvm"
echo ""
echo "SSH Key: /home/j_kro/.ssh/id_rsa"
echo ""
echo "Test connections:"
echo "  ssh nexus 'echo Nexus: \$(nproc) cores'"
echo "  ssh forge 'echo Forge: \$(nproc) cores'"
echo "  ssh sentry 'echo Sentry: \$(nproc) cores'"
echo ""

# ============================================================================
# CUDA AND ML CONFIGURATION
# ============================================================================

echo "🎮 CUDA AND ML CONFIGURATION"
echo "---------------------------"
echo ""
echo "NVIDIA Driver: beta (open-source kernel modules)"
echo "CUDA Version: 12.8"
echo ""
echo "Binary Caches (substituters):"
echo "  - cache.nixos.org"
echo "  - cuda-maintainers.cachix.org ⭐ ESSENTIAL"
echo "  - nix-community.cachix.org"
echo "  - nixpkgs-wayland.cachix.org"
echo "  - nix-gaming.cachix.org"
echo "  - ezkea.cachix.org"
echo ""
echo "CUDA Packages in system-packages.nix:"
echo "  - cudaPackages.cudatoolkit"
echo "  - cudaPackages.cudnn"
echo "  - cudaPackages.libcufft"
echo "  - cudaPackages.libcusparse"
echo "  - python312Packages.torchWithCuda ⚠️  BUILDS FROM SOURCE"
echo "  - python312Packages.tensorflowWithCuda ⚠️  BUILDS FROM SOURCE"
echo ""
echo "Environment Variables (zephyr):"
echo "  CUDA_PATH = \${pkgs.cudaPackages.cuda_cudart}"
echo "  LD_LIBRARY_PATH = /run/opengl-driver/lib:\${cudaPackages.cuda_cudart}/lib:..."
echo ""

# ============================================================================
# ZEN BROWSER ISSUE
# ============================================================================

echo "🌐 ZEN BROWSER ISSUE"
echo "--------------------"
echo ""
echo "Problem: Zen Browser requires building Firefox from source"
echo "Build time: 30-60 minutes"
echo ""
echo "Solution: Pin to specific version to use cached build"
echo ""
echo "Current (unpinned):"
echo "  zen-browser.url = \"github:0xc000022070/zen-browser-flake\";"
echo ""
echo "Should be (pinned):"
echo "  zen-browser.url = \"github:0xc000022070/zen-browser-flake/e97c8e719c7e2567ccf86d279f73ade1dbf72373\";"
echo ""
echo "Location: Commit 15ceb90 on refactor/layer-separation branch"
echo ""
echo "To apply:"
echo "  git cherry-pick 15ceb90"
echo "  # or switch to refactor/layer-separation branch"
echo ""

# ============================================================================
# MINING SERVICES
# ============================================================================

echo "⛏️  MINING SERVICES"
echo "------------------"
echo ""
echo "Services:"
echo "  - xmrig.service (CPU mining)"
echo "  - lolminer-nvidia.service (GPU mining)"
echo ""
echo "Configuration (hosts/zephyr/configuration.nix):"
echo "  services.mining.enable = true;"
echo "  services.mining.xmrig.enable = true;"
echo "  services.mining.xmrig.threads = 16;"
echo "  services.mining.lolminer.enable = true;"
echo "  services.mining.lolminer.nvidia.devices = \"0\";"
echo ""
echo "Recent Fix:"
echo "  - Fixed nvidia-smi path in modules/mining.nix"
echo "  - Changed from hardcoded to config.boot.kernelPackages.nvidiaPackages.beta"
echo ""
echo "Start mining:"
echo "  sudo systemctl start xmrig"
echo "  sudo systemctl start lolminer-nvidia"
echo ""

# ============================================================================
# COMMON COMMANDS
# ============================================================================

echo "⚡ COMMON COMMANDS"
echo "-----------------"
echo ""
echo "Rebuild system:"
echo "  just switch"
echo "  # or"
echo "  sudo nixos-rebuild switch --flake .#zephyr"
echo ""
echo "Update all inputs (DANGEROUS - triggers rebuilds):"
echo "  nix flake update"
echo "  sudo nixos-rebuild switch --flake .#zephyr --upgrade-all"
echo ""
echo "Check flake:"
echo "  nix flake check"
echo ""
echo "Format code:"
echo "  just format"
echo ""
echo "Check service status:"
echo "  sudo systemctl status xmrig"
echo "  sudo systemctl status lolminer-nvidia"
echo ""
echo "View logs:"
echo "  sudo journalctl -u xmrig -f"
echo "  sudo journalctl -u lolminer-nvidia -f"
echo ""

# ============================================================================
# TODO FOR NEXT SESSION
# ============================================================================

echo "📝 TODO FOR NEXT SESSION"
echo "------------------------"
echo ""
echo "HIGH PRIORITY:"
echo "  1. ⭐ Apply Zen Browser pinning to avoid rebuilds"
echo "     - Cherry-pick commit 15ceb90 from refactor/layer-separation"
echo "     - Or merge refactor/layer-separation into master"
echo ""
echo "  2. ⭐ Complete current rebuild"
echo "     - Monitor: tail -f /tmp/nix-build.log"
echo "     - Verify distributed builds are working"
echo "     - Check: ps aux | grep 'ssh.*nix'"
echo ""
echo "MEDIUM PRIORITY:"
echo "  3. Consider removing PyTorch/TensorFlow from system-packages"
echo "     - They build from source (not in cache)"
echo "     - Comment out lines 88-89 in modules/system-packages.nix"
echo "     - Or use nix shell when needed"
echo ""
echo "  4. Merge refactor/layer-separation to master"
echo "     - Contains valuable improvements"
echo "     - Test thoroughly before merging"
echo ""
echo "LOW PRIORITY:"
echo "  5. Clean up staging branch"
echo "     - Purpose unclear"
echo "     - May need to delete or merge"
echo ""

# ============================================================================
# CONTACT / CONTEXT
# ============================================================================

echo "📞 CONTACT / CONTEXT"
echo "--------------------"
echo ""
echo "User: j_kro"
echo "System: zephyr (main workstation)"
echo "GPU: RTX 3090"
echo "Kernel: linuxPackages_zen"
echo "Desktop: KDE Plasma 6 + Wayland"
echo ""
echo "Cluster: 4 nodes (zephyr, nexus, forge, sentry)"
echo "Total Cores: 78 (32 + 24 + 6 + 16)"
echo ""
echo "Special Requirements:"
echo "  - Gaming (Steam, VR with WiVRn)"
echo "  - Mining (xmrig, lolminer)"
echo "  - AI/ML (CUDA, LM Studio)"
echo "  - MUST keep /etc/nixos on master branch"
echo ""

# ============================================================================
# END
# ============================================================================

echo "=========================================="
echo "Hand-off Complete"
echo "=========================================="
echo ""
echo "Next AI session should:"
echo "  1. Read this hand-off script"
echo "  2. Check current build status"
echo "  3. Apply Zen Browser pinning"
echo "  4. Continue monitoring build"
echo ""
