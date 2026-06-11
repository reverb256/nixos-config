{
  config,
  lib,
  ...
}: let
  cluster = config.networking.cluster;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mkMerge
    ;

  networkingHelper = import ./networking.nix {inherit lib;};
  inherit (networkingHelper) mkNetworkingConfig;

  mkProfileConfig = _profileName: profileCfg:
    mkIf profileCfg.enable (
      (mkNetworkingConfig profileCfg)
      // {
        hardware.profiles = {
          nvidia.enable = profileCfg.nvidia.enable or false;
          nvidia.multiGpu = profileCfg.nvidia.multiGpu or false;
          amdgpu.enable = profileCfg.amdgpu.enable or false;
          amdgpu.wayland = profileCfg.amdgpu.wayland or false;
          monitoring.enable = true;
        };

        profiles.network.tailscale.enable = true;
      }
    );
in {
  options.profiles.node = {
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
          ipAddress = cluster.hosts.zephyr.ip;
          interfaceName = "enp38s0";
          unboundListenAddress = cluster.hosts.zephyr.ip;
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
          ipAddress = cluster.hosts.nexus.ip;
          interfaceName = "enp7s0";
          unboundListenAddress = cluster.hosts.nexus.ip;
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
        type = types.listOf (
          types.submodule {
            options = {
              from = mkOption {type = types.port;};
              to = mkOption {type = types.port;};
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
        default = [];
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
          ipAddress = cluster.hosts.forge.ip;
          interfaceName = "enp0s31f6";
          unboundListenAddress = cluster.hosts.forge.ip;
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
        type = types.listOf (
          types.submodule {
            options = {
              from = mkOption {type = types.port;};
              to = mkOption {type = types.port;};
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
        default = [];
        description = "Extra UDP ports";
      };
    };

    sentry-monitoring = {
      enable = mkEnableOption "Sentry monitoring profile (monitoring + observability)";

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
          ipAddress = cluster.hosts.sentry.ip;
          interfaceName = "enp7s0";
          unboundListenAddress = cluster.hosts.sentry.ip;
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
        type = types.listOf (
          types.submodule {
            options = {
              from = mkOption {type = types.port;};
              to = mkOption {type = types.port;};
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
        default = [];
        description = "Extra UDP ports";
      };

      firewallExtraTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [10250];
        description = "Extra TCP ports";
      };

      firewallExtraTCPPortRanges = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              from = mkOption {type = types.port;};
              to = mkOption {type = types.port;};
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
        default = [];
        description = "Extra UDP ports";
      };
    };
  };

  config = mkMerge [
    (mkProfileConfig "zephyr-workstation" config.profiles.node.zephyr-workstation)
    (mkProfileConfig "nexus-gaming" config.profiles.node.nexus-gaming)
    (mkProfileConfig "forge-mining" config.profiles.node.forge-mining)
    (mkProfileConfig "sentry-monitoring" config.profiles.node.sentry-monitoring)

    (mkIf config.profiles.node.zephyr-workstation.enable {
      profiles.role = {
        workstation = true;
        gaming = true;
        vr = true;
        mining = true;
        aiInference = true;
      };
    })

    (mkIf config.profiles.node.nexus-gaming.enable {
      profiles.role = {
        gaming = true;
        vr = true;
        mining = true;
        aiInference = true;
      };
    })

    (mkIf config.profiles.node.forge-mining.enable {
      profiles.role = {
        mining = true;
      };
    })

    (mkIf config.profiles.node.sentry-monitoring.enable {
      profiles.role = {
        monitoring = true;
      };
    })
  ];
}