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
#
# Networking config generation is delegated to networking.nix (mkNetworkingConfig).
{ config, lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mkMerge
    ;

  # Import the reusable networking config generator
  networkingHelper = import ./networking.nix { inherit lib; };
  mkNetworkingConfig = networkingHelper.mkNetworkingConfig;

  # Helper function to create profile config
  # Uses mkNetworkingConfig for networking and applies hardware/role profiles
  mkProfileConfig =
    _profileName: profileCfg:
    mkIf profileCfg.enable (
      (mkNetworkingConfig profileCfg)
      // {
        # Kubernetes is configured per-host via services.k3s-cluster
        # Node profiles no longer set kubernetes-module (replaced by k3s-cluster)

        # Apply hardware profiles
        hardware.profiles = {
          nvidia.enable = profileCfg.nvidia.enable or false;
          nvidia.multiGpu = profileCfg.nvidia.multiGpu or false;
          amdgpu.enable = profileCfg.amdgpu.enable or false;
          amdgpu.wayland = profileCfg.amdgpu.wayland or false;
          monitoring.enable = true; # All nodes get monitoring
        };

        # Apply network profiles
        profiles.network.tailscale.enable = true;
      }
    );
in
{
  options.profiles.node = {
    # ============================================================================
    # NODE-SPECIFIC PROFILES
    # Each profile bundles role profiles + node-specific configuration
    # ============================================================================

    zephyr-workstation = {
      enable = mkEnableOption "Zephyr workstation profile (control plane + gaming + VR + mining + AI)";

      nvidia = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          multiGpu = true;
        };
        description = "NVIDIA GPU configuration";
      };

      networking = mkOption {
        type = types.attrs;
        default = {
          ipAddress = "10.1.1.110";
          interfaceName = "enp38s0";
          unboundListenAddress = "10.1.1.110";
          wireless.enable = true;
        };
        description = "Networking configuration";
      };

      firewallExtraTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [
          9757
          18789
          18790
          19898
          1234
          8080
          53317
          8888
        ];
        description = "Extra TCP ports";
      };

      firewallExtraUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [
          9757
          9758
          9759
          27031
          27036
          5353
          9947
          53317
        ];
        description = "Extra UDP ports";
      };
    };

    nexus-gaming = {
      enable = mkEnableOption "Nexus gaming profile (gaming + VR + mining + AI)";

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
        default = [ 10250 ];
        description = "Extra TCP ports";
      };

      firewallExtraTCPPortRanges = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              from = mkOption { type = types.port; };
              to = mkOption { type = types.port; };
            };
          }
        );
        default = [
          {
            from = 30000;
            to = 32767;
          }
        ];
        description = "Extra TCP port ranges";
      };

      firewallExtraUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "Extra UDP ports";
      };
    };

    forge-mining = {
      enable = mkEnableOption "Forge mining profile (GPU/CPU mining + AI inference)";

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
        default = [ 10250 ];
        description = "Extra TCP ports";
      };

      firewallExtraTCPPortRanges = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              from = mkOption { type = types.port; };
              to = mkOption { type = types.port; };
            };
          }
        );
        default = [
          {
            from = 30000;
            to = 32767;
          }
        ];
        description = "Extra TCP port ranges";
      };

      firewallExtraUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "Extra UDP ports";
      };
    };

    sentry-monitoring = {
      enable = mkEnableOption "Sentry monitoring profile (CPU mining + AI inference)";

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
          ipAddress = "10.1.1.140";
          interfaceName = "enp7s0";
          unboundListenAddress = "10.1.1.140";
          wireless.enable = false;
        };
        description = "Networking configuration";
      };

      firewallExtraTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [ 10250 ];
        description = "Extra TCP ports";
      };

      firewallExtraTCPPortRanges = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              from = mkOption { type = types.port; };
              to = mkOption { type = types.port; };
            };
          }
        );
        default = [
          {
            from = 30000;
            to = 32767;
          }
        ];
        description = "Extra TCP port ranges";
      };

      firewallExtraUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "Extra UDP ports";
      };
    };

    # ============================================================================
    # GENERIC PROFILES (for custom nodes)
    # ============================================================================

    kubernetes-control-plane = {
      enable = mkEnableOption "Kubernetes control plane node (legacy — use k3s-cluster instead)";

      networking = mkOption {
        type = types.attrs;
        default = {
          unboundListenAddress = "10.1.1.110";
        };
        description = "Networking configuration";
      };
    };

    kubernetes-worker = {
      enable = mkEnableOption "Kubernetes worker node (legacy — use k3s-cluster instead)";

      networking = mkOption {
        type = types.attrs;
        default = {
          unboundListenAddress = "10.1.1.120";
        };
        description = "Networking configuration";
      };

      firewallExtraTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [ 10250 ];
        description = "Extra TCP ports";
      };

      firewallExtraTCPPortRanges = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              from = mkOption { type = types.port; };
              to = mkOption { type = types.port; };
            };
          }
        );
        default = [
          {
            from = 30000;
            to = 32767;
          }
        ];
        description = "Extra TCP port ranges";
      };

      firewallExtraUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "Extra UDP ports";
      };
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
