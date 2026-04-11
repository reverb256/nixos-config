# Forge Host Configuration - GPU Mining Rig
# 10.1.1.130 - 6 cores, 2x RTX 4060 + 2x RX 5700 XT
# Features: Mining only (no gaming/VR), ROCm + CUDA
{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    # Monitoring configuration
    ./monitoring.nix
    # Firewall rules
    ./firewall.nix
    # Hardware (GPU compute, AMD/NVIDIA management, ROCm, fan curves)
    ./hardware.nix
    # Desktop (niri + SDDM auto-login)
    ./desktop.nix
    # Services (Kubernetes, mining, NFS, GPU proxy)
    ./services.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix
    # All other modules (desktop, networking, services, etc.)
    ../../modules/default.nix
    # GPU support (wayland-specific, host-dependent)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix
    ../../modules/hardware/amdgpu-wayland.nix
    ../../modules/hardware/rgb-control.nix
    ../../modules/system/security.nix
    ../../modules/services/podman-support.nix
    # Kubernetes worker node
    ../../modules/services/k3s-cluster.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  clusterNetworking = {
    enable = true;
    hostName = "forge";
    ipAddress = "10.1.1.130";
    interfaceName = lib.mkForce "eno1";
    wireless.enable = false;
    unbound.listenAddress = "10.1.1.130";
  };

  # Enable ULA IPv6 for Calico BGP mesh
  networking.interfaces.eno1.ipv6.addresses = [
    {
      address = "fd00::130";
      prefixLength = 64;
    }
  ];

  # Enable IPv6 for Calico BGP multihop
  boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 0;
  boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = 0;
  boot.kernel.sysctl."net.ipv6.conf.eno1.disable_ipv6" = 0;

  # Disable flake-lock-sync (nixos-shared mount not available)
  systemd.timers.flake-lock-sync.enable = false;

  # ============================================================================
  # MEMORY OPTIMIZATION
  # ============================================================================
  # Forge-specific zswap tuning (Intel i5-9500 needs 20% pool, not 40%)
  kernel-hardening.zswap.maxPoolPercent = 20;

  # ZRAM compressed swap - 25% of 15GB ≈ 4GB
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
    priority = 999;
  };

  # Early OOM prevention
  services.earlyoom = {
    enable = true;
    freeSwapThreshold = 10;
    enableNotifications = true;
  };

  # VM tuning for memory-constrained mining node (15GB RAM)
  boot.kernel.sysctl."vm.min_free_kbytes" = lib.mkForce 524288;

  # ============================================================================
  # NODE PROFILE
  # ============================================================================
  profiles.node.forge-mining.enable = true;
  services.ai-inference.backend.type = "llama-cpp";

  # ============================================================================
  # BOOT CONFIGURATION
  # ============================================================================
  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;

  # ============================================================================
  # SYSTEM STATE
  # ============================================================================
  system.stateVersion = "26.05";
}
