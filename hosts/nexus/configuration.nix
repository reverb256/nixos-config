# Nexus Host Configuration - Build and Backup Node
# 10.1.1.120 - 24 cores, 1x RTX 3060 Ti
# Features: Gaming + VR, MCP Servers, Storage (Garage S3, NFS)
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
    # Hardware (GPU, storage mounts, kernel params)
    ./hardware.nix
    # Desktop (Niri + Plasma workstation role)
    ./desktop.nix
    # Services (K3s, storage, mining, NFS, monitoring)
    ./services.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # AI Inference Service
    ./ai-inference.nix

    # All other modules
    ../../modules/default.nix

    # NVIDIA GPU Wayland support
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix
    ../../modules/hardware/rgb-control.nix

    # Nexus-specific modules
    ../../modules/security/aistor-secrets.nix
    ../../modules/services/podman-support.nix

    # Kubernetes
    ../../modules/services/k3s-cluster.nix
    ../../modules/services/keepalived-vip.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  clusterNetworking = {
    enable = true;
    hostName = "nexus";
    ipAddress = "10.1.1.120";
    interfaceName = "enp7s0";
    wireless = {
      enable = true;
      ipAddress = "10.1.1.125";
    };
    unbound.listenAddress = "10.1.1.120";
  };

  # FIX: Disable interface renaming - use actual interface names
  systemd.network.links = lib.mkForce { };

  # Disable flake-lock-sync (nixos-shared mount not available)
  services.flake-lock-sync.enable = lib.mkForce false;
  systemd.timers.flake-lock-sync.enable = false;

  # Populate /etc/hosts from central cluster configuration
  # Stylix theme — Catppuccin Mocha (warm, rich hub — storage + GPU compute)
  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    image = ../../modules/desktop/wallpapers/catppuccin-mocha-bg.jpg;
  };

  networking.cluster-hosts = {
    enable = true;
    populateLocal = true;
  };

  # ============================================================================
  # NODE PROFILE
  # ============================================================================
  profiles.node.nexus-gaming.enable = true;

  # ============================================================================
  # MONITORING - Prometheus, Grafana, AlertManager
  # ============================================================================
  # Nexus hosts the cluster monitoring stack (46GB RAM capacity)
  profiles.monitoring.enable = true;

  # ============================================================================
  # SECURITY
  # ============================================================================
  security.caddyCa.enable = true;

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
