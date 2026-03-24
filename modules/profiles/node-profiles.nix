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
  inherit (lib) mkEnableOption mkOption types mkIf mkMerge;

  # Helper function to create profile config
  mkProfileConfig = _profileName: profileCfg:
    mkIf profileCfg.enable (
      let
        # Extract networking config - handle both nested and direct formats
        networkingCfgBase =
          profileCfg.networking or {
            ipAddress = profileCfg.ipAddress or null;
            interfaceName = profileCfg.interfaceName or null;
            unboundListenAddress = profileCfg.unboundListenAddress or null;
            wireless = profileCfg.wireless or {enable = false;};
          };
        # Ensure wireless has a default value
        networkingCfg =
          networkingCfgBase
          // {
            wireless = networkingCfgBase.wireless or {enable = false;};
          };
      in {
        # Apply networking configuration (only if ipAddress is set)
        clusterNetworking = mkIf (networkingCfg.ipAddress != null) {
          enable = true;
          inherit (networkingCfg) ipAddress;
          inherit (networkingCfg) interfaceName;
          wireless = lib.mkDefault networkingCfg.wireless;
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
          monitoring.enable = true; # All nodes get monitoring
        };

        # Apply network profiles
        profiles.network.tailscale.enable = true;

        # Networking configuration
        networking = {
          # Disable DHCP if requested
          dhcpcd.enable = mkIf (profileCfg.disableDHCP or false) (lib.mkForce false);

          # Apply extra firewall rules
          firewall = {
            allowedTCPPorts = profileCfg.firewallExtraTCPPorts or [];
            allowedTCPPortRanges = profileCfg.firewallExtraTCPPortRanges or [];
            allowedUDPPorts = profileCfg.firewallExtraUDPPorts or [];
          };
        };
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
          masterAddress = "10.1.1.100"; # VIP for HA
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
      networking = mkOption {
        type = types.attrs;
        default = {
          ipAddress = "10.1.1.110";
          interfaceName = "enp38s0"; # Native hardware interface name
          unboundListenAddress = "10.1.1.110";
          wireless.enable = true;
        };
        description = "Networking configuration";
      };

      # Firewall ports (beyond cluster defaults)
      firewallExtraTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [
          9757 # WiVRn main port
          18789 # Steam Remote Play
          18790 # Steam Remote Play (secondary)
          19898 # Moonlight/GameStream + Spacebot Web UI
          1234 # LM Studio API server
          8080 # AI Inference Gateway
          53317 # LocalSend (file sharing)
          8888 # CFSSL CA API server
        ];
        description = "Extra TCP ports";
      };

      firewallExtraUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [
          9757
          9758
          9759 # WiVRn
          27031
          27036 # Steam UDP
          5353 # mDNS
          9947 # WiVRn
          53317 # LocalSend (multicast)
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
          masterAddress = "10.1.1.100"; # VIP for HA
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
          interfaceName = "enp7s0"; # Native hardware interface name
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
        type = types.listOf (types.submodule {
          options = {
            from = mkOption {type = types.port;};
            to = mkOption {type = types.port;};
          };
        });
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
          masterAddress = "10.1.1.100"; # VIP for HA
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
          interfaceName = "enp0s31f6"; # Native hardware interface name
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
        type = types.listOf (types.submodule {
          options = {
            from = mkOption {type = types.port;};
            to = mkOption {type = types.port;};
          };
        });
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
        default = [8472];
        description = "Extra UDP ports";
      };
    };

    sentry-monitoring = {
      enable = mkEnableOption "Sentry monitoring profile (CPU mining + AI inference)";

      kubernetes = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          roles = ["node"];
          masterAddress = "10.1.1.100"; # VIP for HA
        };
        description = "Kubernetes configuration";
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
          ipAddress = "10.1.1.140";
          interfaceName = "enp7s0"; # Native hardware interface name
          unboundListenAddress = "10.1.1.140";
          wireless.enable = false;
        };
        description = "Networking configuration";
      };

      firewallExtraTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [10250];
        description = "Extra TCP ports";
      };

      firewallExtraTCPPortRanges = mkOption {
        type = types.listOf (types.submodule {
          options = {
            from = mkOption {type = types.port;};
            to = mkOption {type = types.port;};
          };
        });
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
        default = [8472];
        description = "Extra UDP ports";
      };
    };

    # ============================================================================
    # GENERIC PROFILES (for custom nodes)
    # ============================================================================

    kubernetes-control-plane = {
      enable = mkEnableOption "Kubernetes control plane node";

      kubernetes = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          roles = ["master" "node"];
          masterAddress = "10.1.1.100"; # VIP for HA
        };
        description = "Kubernetes configuration";
      };

      networking = mkOption {
        type = types.attrs;
        default = {
          unboundListenAddress = "10.1.1.110";
        };
        description = "Networking configuration";
      };
    };

    kubernetes-worker = {
      enable = mkEnableOption "Kubernetes worker node";

      kubernetes = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          roles = ["node"];
          masterAddress = "10.1.1.100"; # VIP for HA
        };
        description = "Kubernetes configuration";
      };

      networking = mkOption {
        type = types.attrs;
        default = {
          unboundListenAddress = "10.1.1.120";
        };
        description = "Networking configuration";
      };

      firewallExtraTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [10250];
        description = "Extra TCP ports";
      };

      firewallExtraTCPPortRanges = mkOption {
        type = types.listOf (types.submodule {
          options = {
            from = mkOption {type = types.port;};
            to = mkOption {type = types.port;};
          };
        });
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
        default = [8472];
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
