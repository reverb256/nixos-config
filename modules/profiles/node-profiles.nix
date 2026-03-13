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
      # Extract networking config - handle both nested and direct formats
      networkingCfg = profileCfg.networking or {
        ipAddress = profileCfg.ipAddress or null;
        interfaceName = profileCfg.interfaceName or null;
        unboundListenAddress = profileCfg.unboundListenAddress or null;
        wireless = profileCfg.wireless or { enable = false; };
      };
    in {
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

      # Apply Kubernetes configuration
      services.kubernetes-module = mkIf (profileCfg ? kubernetes && profileCfg.kubernetes.enable) {
        inherit (profileCfg.kubernetes) enable roles masterAddress;
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

      # Node-specific settings
      kubernetes = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          roles = ["master" "node"];
          masterAddress = "10.1.1.110";
        };
        description = "Kubernetes configuration";
      };

      # Hardware-specific
      nvidia = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          multiGpu = true;
        };
        description = "NVIDIA GPU configuration";
      };

      # Networking
      ipAddress = mkOption {
        type = types.str;
        default = "10.1.1.110";
        description = "Node IP address";
      };

      interfaceName = mkOption {
        type = types.str;
        default = "enp38s0";
        description = "Network interface name";
      };

      unboundListenAddress = mkOption {
        type = types.str;
        default = "10.1.1.110";
        description = "Unbound DNS listen address";
      };

      wireless = mkOption {
        type = types.attrs;
        default = { enable = true; };
        description = "Wireless configuration";
      };

      # Firewall ports (beyond cluster defaults)
      firewallExtraTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [
          9757    # WiVRn main port
          18789   # Steam Remote Play
          18790   # Steam Remote Play (secondary)
          19898   # Moonlight/GameStream + Spacebot Web UI
          1234    # LM Studio API server
          8080    # AI Inference Gateway
          53317   # LocalSend (file sharing)
          8888    # CFSSL CA API server
        ];
        description = "Extra TCP ports";
      };

      firewallExtraUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [
          9757 9758 9759  # WiVRn
          27031 27036     # Steam UDP
          5353           # mDNS
          9947           # WiVRn
          53317          # LocalSend (multicast)
        ];
        description = "Extra UDP ports";
      };
    };

    nexus-gaming = {
      enable = mkEnableOption "Nexus gaming profile (gaming + VR + mining + AI)";

      kubernetes = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          roles = ["node"];
          masterAddress = "10.1.1.110";
        };
        description = "Kubernetes configuration";
      };

      nvidia = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          multiGpu = false;
        };
        description = "NVIDIA GPU configuration";
      };

      networking = mkOption {
        type = types.attrs;
        default = {
          ipAddress = "10.1.1.120";
          interfaceName = "enp7s0";
          unboundListenAddress = "10.1.1.120";
          wireless.enable = true;
        };
        description = "Networking configuration";
      };

      firewallExtraTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [10250];
        description = "Extra TCP ports";
      };

      firewallExtraTCPPortRanges = mkOption {
        type = types.listOf (types.submod {
          options = {
            from = mkOption { type = types.port; };
            to = mkOption { type = types.port; };
          };
        });
        default = [{ from = 30000; to = 32767; }];
        description = "Extra TCP port ranges";
      };

      firewallExtraUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [8472];
        description = "Extra UDP ports";
      };
    };

    forge-mining = {
      enable = mkEnableOption "Forge mining profile (GPU/CPU mining + AI inference)";

      kubernetes = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          roles = ["node"];
          masterAddress = "10.1.1.110";
        };
        description = "Kubernetes configuration";
      };

      nvidia = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          multiGpu = true;
        };
        description = "NVIDIA GPU configuration";
      };

      amdgpu = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          wayland = true;
        };
        description = "AMD GPU configuration";
      };

      networking = mkOption {
        type = types.attrs;
        default = {
          ipAddress = "10.1.1.130";
          interfaceName = "enp0s31f6";
          unboundListenAddress = "10.1.1.130";
          wireless.enable = false;
        };
        description = "Networking configuration";
      };

      disableDHCP = mkOption {
        type = types.bool;
        default = true;
        description = "Disable DHCP for static IP";
      };

      firewallExtraTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [10250];
        description = "Extra TCP ports";
      };

      firewallExtraTCPPortRanges = mkOption {
        type = types.listOf (types.submod {
          options = {
            from = mkOption { type = types.port; };
            to = mkOption { type = types.port; };
          };
        });
        default = [{ from = 30000; to = 32767; }];
        description = "Extra TCP port ranges";
      };

      firewallExtraUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [8472];
        description = "Extra UDP ports";
      };
    };

    sentry-monitoring = {
      enable = mkEnableOption "Sentry monitoring profile (CPU mining + AI inference)";

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
        roles = ["master" "node"];  # NixOS services.kubernetes uses "master", not "control-plane"
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

    # ============================================================================
    # ROLE PROFILE ASSIGNMENTS
    # ============================================================================
    # Each node profile assigns its corresponding role profiles
    # ============================================================================

    # Zephyr workstation role profiles
    (mkIf config.profiles.node.zephyr-workstation.enable {
      profiles.role = {
        workstation = true;
        gaming = true;
        vr = true;
        mining = true;
        aiInference = true;
      };
    })

    # Nexus gaming role profiles
    (mkIf config.profiles.node.nexus-gaming.enable {
      profiles.role = {
        gaming = true;
        vr = true;
        mining = true;
        aiInference = true;
      };
    })

    # Forge mining role profiles
    (mkIf config.profiles.node.forge-mining.enable {
      profiles.role = {
        mining = true;
        aiInference = true;
      };
    })

    # Sentry monitoring role profiles
    (mkIf config.profiles.node.sentry-monitoring.enable {
      profiles.role = {
        mining = true;
        aiInference = true;
      };
    })
  ];
}
