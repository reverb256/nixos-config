# Sentry Host Configuration - Monitoring Server
# 10.1.1.140 - 16 cores, RX 5600 XT
# Features: Gaming only (no VR), CPU mining, ROCm
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
    # Hardware (AMD GPU, ROCm, RGB, kernel params)
    ./hardware.nix
    # Desktop (niri + SDDM)
    ./desktop.nix
    # Services (K3s, nginx, mining, NFS, Syncthing, llamafile)
    ./services.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # All other modules
    ../../modules/default.nix

    # AMD GPU Wayland optimizations
    ../../modules/hardware/amdgpu-wayland.nix
    ../../modules/hardware/rgb-control.nix

    # Podman support
    ../../modules/services/podman-support.nix

    # Kubernetes
    ../../modules/services/k3s-cluster.nix
    ../../modules/services/keepalived-vip.nix
  ];

  # Stylix theme — Dracula (dark, alert — monitoring + logging)
  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/dracula.yaml";
    image = ../../modules/desktop/wallpapers/dracula-bg.png;
  };

  # Enable niri compositor with auto-login (moved to desktop.nix)

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  clusterNetworking = {
    enable = true;
    hostName = "sentry";
    ipAddress = "10.1.1.140";
    interfaceName = "enp7s0";
    wireless.enable = false;
    unbound.listenAddress = "10.1.1.140";
  };

  # Disable flake-lock-sync (nixos-shared mount not available)
  services.flake-lock-sync.enable = lib.mkForce false;
  systemd.timers.flake-lock-sync.enable = false;

  # ============================================================================
  # NODE PROFILE
  # ============================================================================
  profiles.node.sentry-monitoring.enable = true;

  # Use llama-cpp backend (sentry doesn't have ZAI API key)
  services.ai-inference.backend.type = "llama-cpp";

  # ============================================================================
  # BOOT CONFIGURATION
  # ============================================================================
  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;
  boot.loader.timeout = lib.mkDefault 5;

  # ============================================================================
  # SYSTEM STATE
  # ============================================================================
  system.stateVersion = "26.05";
}
