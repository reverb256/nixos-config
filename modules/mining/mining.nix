# Mining services module
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.mining;
  hostname = config.networking.hostName;
  defaultWallet = "krxXVNVMM7.${hostname}";

  # Security hardening template for mining services
  miningHardening = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    ProtectHostname = true;
    RestrictRealtime = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ReadOnlyPaths = "/";
    ReadWritePaths = [
      "/var/lib/mining"
      "/var/log/mining"
    ];
    CapabilityBoundingSet = "CAP_SYS_NICE";
    AmbientCapabilities = "CAP_SYS_NICE";
  };

  # NVIDIA GPU power limit script
  nvidiaGpuPowerLimitScript = pkgs.writeShellScript "nvidia-gpu-power-limit" ''
    PATH=/run/current-system/sw/bin:$PATH
    echo "Setting NVIDIA GPU power limits..."
    nvidia-smi -pm 1
    echo "GPU power limits managed by nvidia-persistenced + gpu-workload-monitor"
  '';

  # AMD GPU power limit script
  amdGpuPowerLimitScript = pkgs.writeShellScript "amd-gpu-power-limit" ''
    echo "AMD GPU power limits managed by rocm-smi"
  '';
in
{
  options.services.mining = {
    enable = mkEnableOption "Robust Mining Services";
    user = mkOption {
      type = types.str;
      default = "mining";
      description = "User to run mining services as";
    };

      threads = mkOption {
        type = types.int;
        default = 16;
        description = "Number of CPU threads for mining";
      };
      pool = mkOption {
        type = types.str;
        default = "xtm-rx-us.kryptex.network:8038";
        description = "Mining pool URL";
      };
      wallet = mkOption {
        type = types.str;
        default = defaultWallet;
        description = "Wallet address";
      };
      password = mkOption {
        type = types.str;
        default = "x";
        description = "Pool password";
      };
      tls = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to use TLS for pool connection";
      };
      httpTokenFile = mkOption {
        type = types.path;
        description = "Path to the HTTP API token file (managed by agenix)";
      };
    };
  };

  config = mkIf cfg.enable {
    # Assertions
    assertions = [
      {
        message = ''
          Configure a mining pool:
        '';
      }
      {
        message = ''
        '';
      }
      {
      }
    ];

    # Create mining user and group
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = "mining";
      extraGroups = ["video" "render"];
    };
    users.groups.mining = { };

    # Huge pages + MSR for CPU mining
    boot = {
      kernel.sysctl."vm.nr_hugepages" = 1280;
      kernelModules = ["msr"];
      kernelParams = [
        "hugepagesz=1G"
        "hugepages=3"
        "msr.allow_writes=on"
      ];
    };

    services.udev.extraRules = ''
      KERNEL=="msr", MODE="0666"
    '';

    fileSystems."/dev/hugepages-1gb" = {
      device = "none";
      fsType = "hugetlbfs";
      options = ["pagesize=1G"];
    };

    systemd.tmpfiles.rules = [
      "L+ /dev/cpu/msr - - - - /dev/cpu/0/msr"
      "d /var/lib/mining 0750 ${cfg.user} mining -"
      "d /var/log/mining 0750 ${cfg.user} mining -"
    ];

      text = builtins.toJSON {
        api = {
          id = null;
          "worker-id" = null;
        };
        http = {
          enabled = true;
          host = "127.0.0.1";
          port = 8081;
          restricted = false;
        };
        pools = [
          {
            keepalive = true;
            nicehash = false;
          }
          {
            url = "xtm-rx-eu.kryptex.network:8038";
            keepalive = true;
            nicehash = false;
          }
          {
            url = "xtm-rx-asia.kryptex.network:8038";
            keepalive = true;
            nicehash = false;
          }
        ];
        randomx = {
          "1gb-pages" = true;
          mode = "fast";
        };
        asm = true;
        cpu = {
          enabled = true;
          "huge-pages" = true;
          "huge-pages-jit" = false;
          "hw-aes" = null;
          priority = null;
          "memory-pool" = false;
          yield = true;
        };
        logging = {
          type = "stdout";
          level = "0";
        };
      };
    };

    # Systemd services
    systemd = {
      targets.mining = {
        description = "All mining services";
          ++ ["network-online.target"];
        after = ["network-online.target"];
      };

      services = {
          wantedBy = ["multi-user.target"];
          after = ["network.target"];
          serviceConfig = {
            User = cfg.user;
            Group = "mining";
            Slice = "mining.slice";
            ExecStartPre =
              let
              in
                set -euo pipefail
                TOKEN_FILE="${tokenFile}"
                RUNTIME_CONFIG="${runtimeConfig}"
                CONFIG="''${RUNTIME_CONFIG:-${configFile}}"
                if [ -r "$CONFIG" ]; then
                else
                fi
              '';
            Restart = "always";
            RestartSec = "30s";
            LimitMEMLOCK = "4G";
          }
          // miningHardening;
      };
    };

    networking.firewall.interfaces.lo.allowedTCPPorts = [8081];
  };
}
