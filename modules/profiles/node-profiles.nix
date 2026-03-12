# Node Profile System
# Centralized role-based profiles to eliminate DRY violations
#
# USAGE:
#   profiles.node.zephyr-workstation.enable = true;
#   profiles.node.kubernetes-worker.enable = true;
#
# This replaces manual profile declaration:
#   OLD: profiles.role = { gaming = true; mining = true; };
#   NEW: profiles.node.gaming-mining.enable = true;
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkOption types mkIf mkMerge mapAttrsToList;

  # Helper function to create profile config
  mkProfileConfig = profileName: profileCfg: mkIf profileCfg.enable (
    let
      roleProfiles = profileCfg.roleProfiles or {};

      # Extract networking config - handle both nested and direct formats
      networkingCfg = profileCfg.networking or {
        ipAddress = profileCfg.ipAddress or null;
        interfaceName = profileCfg.interfaceName or null;
        unboundListenAddress = profileCfg.unboundListenAddress or null;
        wireless = profileCfg.wireless or { enable = false; };
      };
    in {
      # Apply role profiles (if any)
      profiles.role = roleProfiles;

      # Apply Kubernetes configuration
      services.kubernetes-module = mkIf (profileCfg ? kubernetes && profileCfg.kubernetes.enable) {
        inherit (profileCfg.kubernetes) enable roles masterAddress;
      };

      # Apply networking configuration (only if ipAddress is set)
      clusterNetworking = mkIf (networkingCfg.ipAddress != null) {
        enable = true;
        ipAddress = networkingCfg.ipAddress;
        interfaceName = networkingCfg.interfaceName;
        wireless = networkingCfg.wireless;
        unbound = {
          enable = true;
          listenAddress = networkingCfg.unboundListenAddress;
        };
      };

      # Apply hardware profiles
      hardware.profiles = {
        nvidia.enable = profileCfg.nvidia.enable or false;
        nvidia.multiGpu = profileCfg.nvidia.multiGpu or false;
        amdgpu.enable = profileCfg.amdgpu.enable or false;
        amdgpu.wayland = profileCfg.amdgpu.wayland or false;
        monitoring.enable = true;  # All nodes get monitoring
      };

      # Apply network profiles
      profiles.network.tailscale.enable = true;

      # Disable DHCP if requested
      networking.dhcpcd.enable = mkIf (profileCfg.disableDHCP or false) (lib.mkForce false);

      # Apply extra firewall rules
      networking.firewall.allowedTCPPorts = profileCfg.firewallExtraTCPPorts or [];
      networking.firewall.allowedTCPPortRanges = profileCfg.firewallExtraTCPPortRanges or [];
      networking.firewall.allowedUDPPorts = profileCfg.firewallExtraUDPPorts or [];
    }
  );
in {
  options.profiles.node = {
    # ============================================================================
    # NODE-SPECIFIC PROFILES
    # Each profile bundles role profiles + node-specific configuration
    # ============================================================================

    zephyr-workstation = {
      enable = mkEnableOption "Zephyr workstation profile (control plane + gaming + VR + mining + AI)";

      # Role profiles
      roleProfiles = {
        workstation = true;
        gaming = true;
        vr = true;
        mining = true;
        aiInference = true;
      };

      # Node-specific settings
      kubernetes = {
        enable = true;
        roles = ["control-plane" "node"];
        masterAddress = "10.1.1.110";
      };

      # Hardware-specific
      nvidia = {
        enable = true;
        multiGpu = true;  # RTX 3090 + others
      };

      # Networking
      ipAddress = "10.1.1.110";
      interfaceName = "enp38s0";
      unboundListenAddress = "10.1.1.110";

      # Firewall ports (beyond cluster defaults)
      firewallExtraTCPPorts = [
        9757    # WiVRn main port
        18789   # Steam Remote Play
        18790   # Steam Remote Play (secondary)
        19898   # Moonlight/GameStream + Spacebot Web UI
        1234    # LM Studio API server
        8080    # AI Inference Gateway
        53317   # LocalSend (file sharing)
        8888    # CFSSL CA API server
      ];
      firewallExtraUDPPorts = [
        9757 9758 9759  # WiVRn
        27031 27036     # Steam UDP
        5353           # mDNS
        9947           # WiVRn
        53317          # LocalSend (multicast)
      ];
    };

    nexus-gaming = {
      enable = mkEnableOption "Nexus gaming profile (gaming + VR + mining + AI)";

      roleProfiles = {
        gaming = true;
        vr = true;
        mining = true;
        aiInference = true;
      };

      kubernetes = {
        enable = true;
        roles = ["node"];
        masterAddress = "10.1.1.110";
      };

      nvidia = {
        enable = true;
        multiGpu = false;  # Single RTX 3060 Ti
      };

      networking = {
        ipAddress = "10.1.1.120";
        interfaceName = "enp7s0";
        unboundListenAddress = "10.1.1.120";
        wireless.enable = true;
      };

      firewallExtraTCPPorts = [
        10250  # Kubelet API
      ];
      firewallExtraTCPPortRanges = [
        { from = 30000; to = 32767; }  # NodePort range
      ];
      firewallExtraUDPPorts = [
        8472  # Flannel VXLAN
      ];

      # Additional modules
      extraImports = [
        ../../modules/hardware/nvidia-common.nix
        ../../modules/hardware/nvidia-wayland.nix
        ../../modules/desktop/gamescope-tty.nix
        ../../modules/services/mcp-servers.nix
        ../../modules/services/podman-support.nix
      ];
    };

    forge-mining = {
      enable = mkEnableOption "Forge mining profile (GPU/CPU mining + AI inference)";

      roleProfiles = {
        mining = true;
        aiInference = true;
      };

      kubernetes = {
        enable = true;
        roles = ["node"];
        masterAddress = "10.1.1.110";
      };

      # Multi-vendor GPU (NVIDIA + AMD)
      nvidia = {
        enable = true;
        multiGpu = true;  # 2x RTX 4060
      };
      amdgpu = {
        enable = true;
        wayland = true;
      };

      networking = {
        ipAddress = "10.1.1.130";
        interfaceName = "enp0s31f6";
        unboundListenAddress = "10.1.1.130";
        wireless.enable = false;  # Mining rig - no WiFi
      };

      # Disable DHCP (static IP only)
      disableDHCP = true;

      firewallExtraTCPPorts = [
        10250  # Kubelet API
      ];
      firewallExtraTCPPortRanges = [
        { from = 30000; to = 32767; }  # NodePort range
      ];
      firewallExtraUDPPorts = [
        8472  # Flannel VXLAN
      ];

      extraImports = [
        ../../modules/hardware/nvidia-common.nix
        ../../modules/hardware/nvidia-wayland.nix
        ../../modules/hardware/amdgpu-wayland.nix
        ../../modules/system/security.nix
        ../../modules/services/podman-support.nix
      ];
    };

    sentry-monitoring = {
      enable = mkEnableOption "Sentry monitoring profile (CPU mining + AI inference)";

      roleProfiles = {
        mining = true;
        aiInference = true;
      };

      kubernetes = {
        enable = true;
        roles = ["node"];
        masterAddress = "10.1.1.110";
      };

      amdgpu = {
        enable = true;
        wayland = true;
      };

      networking = {
        ipAddress = "10.1.1.140";
        interfaceName = "enp7s0";
        unboundListenAddress = "10.1.1.140";
        wireless.enable = false;
      };

      firewallExtraTCPPorts = [
        10250  # Kubelet API
      ];
      firewallExtraTCPPortRanges = [
        { from = 30000; to = 32767; }  # NodePort range
      ];
      firewallExtraUDPPorts = [
        8472  # Flannel VXLAN
      ];

      extraImports = [
        ../../modules/hardware/amdgpu-wayland.nix
        ../../modules/services/podman-support.nix
      ];
    };

    # ============================================================================
    # GENERIC PROFILES (for custom nodes)
    # ============================================================================

    kubernetes-control-plane = {
      enable = mkEnableOption "Kubernetes control plane node";

      kubernetes = {
        enable = true;
        roles = ["control-plane" "node"];
        masterAddress = mkOption {
          type = types.str;
          default = "10.1.1.110";
          description = "API server address";
        };
      };

      # DNS should point to self
      unboundListenAddress = mkOption {
        type = types.str;
        example = "10.1.1.110";
        description = "IP address for Unbound to listen on";
      };
    };

    kubernetes-worker = {
      enable = mkEnableOption "Kubernetes worker node";

      kubernetes = {
        enable = true;
        roles = ["node"];
        masterAddress = mkOption {
          type = types.str;
          default = "10.1.1.110";
          description = "API server address";
        };
      };

      unboundListenAddress = mkOption {
        type = types.str;
        example = "10.1.1.120";
        description = "IP address for Unbound to listen on";
      };

      firewallExtraTCPPorts = [
        10250  # Kubelet API
      ];
      firewallExtraTCPPortRanges = [
        { from = 30000; to = 32767; }  # NodePort range
      ];
      firewallExtraUDPPorts = [
        8472  # Flannel VXLAN
      ];
    };
  };

  # ============================================================================
  # PROFILE IMPLEMENTATION
  # ============================================================================
  config = mkMerge [
    # Zephyr workstation profile
    (mkProfileConfig "zephyr-workstation" config.profiles.node.zephyr-workstation)
    # Nexus gaming profile
    (mkProfileConfig "nexus-gaming" config.profiles.node.nexus-gaming)
    # Forge mining profile
    (mkProfileConfig "forge-mining" config.profiles.node.forge-mining)
    # Sentry monitoring profile
    (mkProfileConfig "sentry-monitoring" config.profiles.node.sentry-monitoring)
    # Generic Kubernetes control plane profile
    (mkProfileConfig "kubernetes-control-plane" config.profiles.node.kubernetes-control-plane)
    # Generic Kubernetes worker profile
    (mkProfileConfig "kubernetes-worker" config.profiles.node.kubernetes-worker)
  ];
}
