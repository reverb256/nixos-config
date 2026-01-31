{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.mining;

  # Use config.boot.kernelPackages.nvidiaPackages.stable for correct driver path
  nvidiaPackage = config.boot.kernelPackages.nvidiaPackages.stable;

  # Minimal wrapper for NVIDIA mining inside steam-run
  lolminerWrapper = pkgs.writeShellScriptBin "lolminer-wrapper" ''
    #!/usr/bin/env bash
    # Just execute lolMiner directly - environment variables are set in systemd service
    exec ${pkgs.lolminer}/bin/lolMiner "$@"
  '';

  # Minimal wrapper for AMD mining inside steam-run
  lolminerAmdWrapper = pkgs.writeShellScriptBin "lolminer-amd-wrapper" ''
    #!/usr/bin/env bash
    # Just execute lolMiner directly - environment variables are set in systemd service
    exec ${pkgs.lolminer}/bin/lolMiner "$@"
  '';

  monitorScript = pkgs.writeShellScriptBin "miner-monitor" ''
    #!/usr/bin/env bash
    API_RESPONSE=$(curl -s http://localhost:4068/summary 2>/dev/null || echo "")
    if [[ -z "$API_RESPONSE" || "$API_RESPONSE" == *"ERROR"* ]]; then
      echo "API check failed - restarting lolMiner"
      systemctl restart lolminer-nvidia
    else
      echo "Mining service healthy"
    fi
  '';
in {
  options.services.mining = {
    enable = mkEnableOption "Robust Mining Services";
    user = mkOption {
      type = types.str;
      default = "j_kro";
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
        default = "krxXVNVMM7.zephyr";
      };
      nvidia = {
        enable = mkEnableOption "NVIDIA GPU Mining";
        devices = mkOption {
          type = types.str;
          default = "0";
        };
        powerLimit = mkOption {
          type = types.int;
          default = 250;
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
        default = "krxXVNVMM7.zephyr";
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
        default = "/run/secrets/mining-api-token";
        description = "Path to the file containing the HTTP API token";
      };
    };
  };

  config = mkIf cfg.enable {
    boot.kernel.sysctl = {
      "vm.nr_hugepages" = 1280;
    };

    environment.systemPackages = [monitorScript lolminerWrapper];

    # Create mining API token file (fallback when agenix is not available)
    systemd.tmpfiles.rules = [
      "d /run/secrets 0750 root root -"
      "f /run/secrets/mining-api-token 0640 root root 'xmrig-api-token'"
    ];

    # XMRig configuration file
    environment.etc."xmrig/config.json" = {
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
          threads = cfg.xmrig.threads;
        };
        logging = {
          type = "stdout";
          level = "0";
        };
      };
    };

    systemd = {
      services = {
        lolminer-nvidia = mkIf cfg.lolminer.nvidia.enable {
          description = "lolMiner NVIDIA Mining Service";
          wantedBy = ["multi-user.target"];
          after = ["NetworkManager.service"];
          requires = [];

          serviceConfig = {
            User = "mining";
            Group = "mining";
            Slice = "mining.slice";
            ExecStartPre = [
              # Set persistent management and power limit for RTX 3090
              "${pkgs.bash}/bin/bash -c 'PATH=/run/current-system/sw/bin:$PATH nvidia-smi -pm 1'"
              # Set power limit to 250W as required for zephyr
              "${pkgs.bash}/bin/bash -c 'PATH=/run/current-system/sw/bin:$PATH nvidia-smi -pl 250 --id=${cfg.lolminer.nvidia.devices}'"
            ];
            ExecStart = "${pkgs.steam-run}/bin/steam-run ${lolminerWrapper}/bin/lolminer-wrapper --algo ${cfg.lolminer.algorithm} --pool ${cfg.lolminer.pool} --user ${cfg.lolminer.wallet} --devices ${cfg.lolminer.nvidia.devices} --apiport ${toString cfg.lolminer.nvidia.apiPort} --mode b --tls 1";
            ExecStopPost = "${pkgs.bash}/bin/bash -c 'PATH=/run/current-system/sw/bin:$PATH nvidia-smi -pl 350 --id=${cfg.lolminer.nvidia.devices} || true'"; # Reset power limit to 350W
            Restart = "always";
            RestartSec = "30s";
            Environment = [
              "GPU_MAX_HEAP_SIZE=100"
              "GPU_MAX_ALLOC_PERCENT=100"
            ];
            NoNewPrivileges = false;
            PrivateTmp = true;
            PrivateDevices = false;
            ProtectKernelTunables = false;
            ProtectControlGroups = false;
            ProtectHostname = false;
            RestrictRealtime = true;
            LimitMEMLOCK = "4G";
          };
        };

        lolminer-amd = mkIf cfg.lolminer.amd.enable {
          description = "lolMiner AMD Mining Service";
          wantedBy = ["multi-user.target"];
          after = ["NetworkManager.service"];

          serviceConfig = {
            User = "j_kro";
            Group = "users";
            Slice = "mining.slice";
            ExecStart = "${pkgs.steam-run}/bin/steam-run ${lolminerAmdWrapper}/bin/lolminer-amd-wrapper --algo ${cfg.lolminer.algorithm} --pool ${cfg.lolminer.pool} --user ${cfg.lolminer.wallet} --devices ${cfg.lolminer.amd.devices} --apiport ${toString cfg.lolminer.amd.apiPort} --mode b --tls 1";
            Restart = "always";
            RestartSec = "30s";
            Environment = [
              "GPU_MAX_HEAP_SIZE=100"
              "GPU_MAX_ALLOC_PERCENT=100"
              "HSA_OVERRIDE_GFX_VERSION=10.3.0"
            ];
            NoNewPrivileges = false;
            PrivateTmp = true;
            PrivateDevices = false;
            ProtectKernelTunables = false;
            ProtectControlGroups = false;
            ProtectHostname = false;
            RestrictRealtime = true;
            LimitMEMLOCK = "4G";
          };
        };

        xmrig = mkIf cfg.xmrig.enable {
          description = "XMRig CPU Mining Service";
          wantedBy = ["multi-user.target"];
          after = ["NetworkManager.service"];

          serviceConfig = {
            User = "root";
            Group = "root";
            Slice = "mining.slice";
            ExecStart = "${pkgs.xmrig}/bin/xmrig -o stratum+ssl://xtm-rx-us.kryptex.network:8038 -u ${cfg.xmrig.wallet} -t ${toString cfg.xmrig.threads} --http-port 8081 --http-access-token-file ${cfg.xmrig.httpTokenFile} --randomx-1gb-pages --randomx-mode=fast --asm=auto";
            Restart = "always";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            RestrictRealtime = true;
            LimitMEMLOCK = "4G";
            CapabilityBoundingSet = "CAP_SYS_ADMIN CAP_SYS_NICE CAP_SYS_RAWIO";
            AmbientCapabilities = "CAP_SYS_ADMIN CAP_SYS_NICE CAP_SYS_RAWIO";
          };
        };

        test-service = {
          description = "Test Service for Mining Module";
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            ExecStart = "/run/current-system/sw/bin/echo 'test service works'";
            Type = "oneshot";
          };
        };

        miner-monitor = mkIf cfg.lolminer.enable {
          script = "${monitorScript}/bin/miner-monitor";
          serviceConfig = {
            Type = "oneshot";
          };
        };
      };

      timers = {
        miner-monitor = mkIf cfg.lolminer.enable {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "5m";
            OnUnitActiveSec = "5m";
            Unit = "miner-monitor.service";
          };
        };
      };
    };
  };
}
