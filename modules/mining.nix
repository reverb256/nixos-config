{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.mining;
  hostname = config.networking.hostName;
  defaultWallet = "krxXVNVMM7.${hostname}";

  # Helper to build lolMiner command arguments
  mkLolminerArgs = deviceCfg:
    concatStringsSep " " [
      "--algo ${cfg.lolminer.algorithm}"
      "--pool ${cfg.lolminer.pool}"
      "--user ${cfg.lolminer.wallet}"
      "--devices ${deviceCfg.devices}"
      "--apiport ${toString deviceCfg.apiPort}"
      "--mode b"
      "--tls 1"
    ];

  # Helper for lolMiner security hardening
  lolminerHardening = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    ProtectHostname = true;
    RestrictRealtime = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ReadOnlyPaths = "/";
    ReadWritePaths = ["/var/lib/mining" "/var/log/mining"];
    CapabilityBoundingSet = "CAP_SYS_NICE";
    AmbientCapabilities = "CAP_SYS_NICE";
  };

  # NVIDIA power limit script
  nvidiaPowerLimitScript = pkgs.writeShellScript "nvidia-powerlimit-pre" ''
    PATH=/run/current-system/sw/bin:$PATH
    nvidia-smi -pm 1 || true
    nvidia-smi -pl ${toString cfg.lolminer.nvidia.powerLimit} || true
  '';

  # System watchdog script - reboots if load stays high
  nexusWatchdogScript = pkgs.writeShellScript "nexus-watchdog" ''
    while true; do
      load=$(cat /proc/loadavg | awk "{print \$1}" | cut -d. -f1)
      if [ "$load" -gt 20 ]; then
        sleep 120
        load2=$(cat /proc/loadavg | awk "{print \$1}" | cut -d. -f1)
        if [ "$load2" -gt 20 ]; then
          echo "High load persists, rebooting..."
          /run/current-system/sw/bin/reboot
        fi
      fi
      sleep 60
    done
  '';
in {
  options.services.mining = {
    enable = mkEnableOption "Robust Mining Services";
    user = mkOption {
      type = types.str;
      default = "mining";
      description = "User to run mining services as";
    };

    lolminer = {
      enable = mkEnableOption "lolMiner Service";
      algorithm = mkOption {
        type = types.str;
        default = "CR29";
      };
      pool = mkOption {
        type = types.str;
        default = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
      };
      wallet = mkOption {
        type = types.str;
        default = defaultWallet;
      };
      nvidia = {
        enable = mkEnableOption "NVIDIA GPU Mining";
        devices = mkOption {
          type = types.str;
          default = "0";
        };
        powerLimit = mkOption {
          type = types.int;
          default = 90;
        };
        apiPort = mkOption {
          type = types.int;
          default = 4068;
        };
      };

      amd = {
        enable = mkEnableOption "AMD GPU Mining";
        devices = mkOption {
          type = types.str;
          default = "1";
        };
        powerLimit = mkOption {
          type = types.int;
          default = 140;
        };
        apiPort = mkOption {
          type = types.int;
          default = 4069;
        };
      };
    };

    xmrig = {
      enable = mkEnableOption "XMRig Service";
      pool = mkOption {
        type = types.str;
        default = "xtm-rx-us.kryptex.network:8038";
      };
      wallet = mkOption {
        type = types.str;
        default = defaultWallet;
      };
      password = mkOption {
        type = types.str;
        default = "x";
      };
      threads = mkOption {
        type = types.int;
        default = 16;
      };
      httpTokenFile = mkOption {
        type = types.path;
        default = "/run/agenix/mining-api-token";
        description = "Path to the HTTP API token file";
      };
    };
  };

  config = mkIf cfg.enable {
    # Create mining user and group
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = "mining";
    };
    users.groups.mining = {};

    boot.kernel.sysctl = {
      "vm.nr_hugepages" = 1280;
    };

    environment.systemPackages = [pkgs.lolminer];

    systemd.tmpfiles.rules = [
      "d /var/lib/mining 0750 ${cfg.user} mining - -"
      "d /var/log/mining 0750 ${cfg.user} mining - -"
    ];

    environment.etc."xmrig/config.json" = mkIf cfg.xmrig.enable {
      text = builtins.toJSON {
        api = {
          id = null;
          "worker-id" = null;
        };
        http = {
          enabled = true;
          host = "127.0.0.1";
          port = 8081;
          "access-token-file" = cfg.xmrig.httpTokenFile;
          restricted = true;
        };
        pools = [
          {
            url = cfg.xmrig.pool;
            user = cfg.xmrig.wallet;
            pass = cfg.xmrig.password or "x";
            tls = true;
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
          inherit (cfg.xmrig) threads;
        };
        logging = {
          type = "stdout";
          level = "0";
        };
      };
    };

    systemd = {
      services = {
        nexus-watchdog = {
          description = "System Watchdog for Stability";
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "simple";
            ExecStart = nexusWatchdogScript;
            Restart = "always";
            RestartSec = "10s";
          };
        };

        lolminer-nvidia = mkIf cfg.lolminer.nvidia.enable {
          description = "lolMiner NVIDIA Mining Service";
          wantedBy = ["multi-user.target"];
          after = ["network.target"];
          serviceConfig =
            {
              User = cfg.user;
              Group = "mining";
              Slice = "mining.slice";
              ExecStartPre = nvidiaPowerLimitScript;
              ExecStart = "${pkgs.lolminer}/bin/lolMiner ${mkLolminerArgs cfg.lolminer.nvidia}";
              Restart = "always";
              RestartSec = "30s";
              Environment = [
                "GPU_MAX_HEAP_SIZE=100"
                "GPU_MAX_ALLOC_PERCENT=100"
              ];
              LimitMEMLOCK = "4G";
            }
            // lolminerHardening;
        };

        lolminer-amd = mkIf cfg.lolminer.amd.enable {
          description = "lolMiner AMD Mining Service";
          wantedBy = ["multi-user.target"];
          after = ["network.target" "amd-gpu-power-mgmt.service"];
          serviceConfig =
            {
              User = cfg.user;
              Group = "mining";
              Slice = "mining.slice";
              ExecStart = "${pkgs.lolminer}/bin/lolMiner ${mkLolminerArgs cfg.lolminer.amd}";
              Restart = "always";
              RestartSec = "30s";
              LimitMEMLOCK = "8G";
            }
            // lolminerHardening;
        };

        xmrig = mkIf cfg.xmrig.enable {
          description = "XMRig CPU Mining Service";
          wantedBy = ["multi-user.target"];
          after = ["network.target"];
          serviceConfig = {
            User = cfg.user;
            Group = "mining";
            Slice = "mining.slice";
            ExecStart = "${pkgs.xmrig}/bin/xmrig -o stratum+ssl://${cfg.xmrig.pool} -u ${cfg.xmrig.wallet} -t ${toString cfg.xmrig.threads} --http-host 0.0.0.0 --http-port 8081 --randomx-1gb-pages --randomx-mode=fast --asm=auto";
            Restart = "always";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ProtectHostname = true;
            RestrictRealtime = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadOnlyPaths = "/";
            ReadWritePaths = ["/var/lib/mining" "/var/log/mining"];
            LimitMEMLOCK = "4G";
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
          };
        };
      };
    };

    networking.firewall.interfaces.lo.allowedTCPPorts = [
      cfg.lolminer.nvidia.apiPort
      cfg.lolminer.amd.apiPort
      8081
    ];
  };
}
