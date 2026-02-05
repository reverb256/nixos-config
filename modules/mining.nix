{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.mining;

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
      default = "mining"; # Default to non-root user
      description = "User to run mining services as (security: never use root)";
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
        default = "/run/agenix/mining-api-token";
        description = "Path to the file containing the HTTP API token (agenix)";
      };
    };
  };

  config = mkIf cfg.enable {
    boot.kernel.sysctl = {
      "vm.nr_hugepages" = 1280;
    };

    environment.systemPackages = [monitorScript lolminerWrapper];

    # Note: Mining API token is managed by agenix in /run/agenix/
    # No tmpfiles rule needed - agenix handles the directory creation

    # Create mining state directory with proper permissions
    systemd.tmpfiles.rules = [
      "d /var/lib/mining 0750 ${cfg.user} mining - -"
      "d /var/log/mining 0750 ${cfg.user} mining - -"
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
            User = cfg.user;
            Group = "mining";
            Slice = "mining.slice";
            Environment = [
              "PATH=/run/current-system/sw/bin:$PATH"
              "GPU_MAX_HEAP_SIZE=100"
              "GPU_MAX_ALLOC_PERCENT=100"
            ];
            ExecStartPre = [
              # Wait for GPU to be ready
              "${pkgs.bash}/bin/bash -c 'sleep 2 && ${config.hardware.nvidia.package}/bin/nvidia-smi || true'"
              # Use direct nvidia-smi path without sudo
              "${pkgs.bash}/bin/bash -c '${config.hardware.nvidia.package}/bin/nvidia-smi -pm 1 || true'"
              # Set power limit using configured value (only if reasonable)
              "${pkgs.bash}/bin/bash -c 'if [ ${toString cfg.lolminer.nvidia.powerLimit} -ge 100 ]; then ${config.hardware.nvidia.package}/bin/nvidia-smi -pl ${toString cfg.lolminer.nvidia.powerLimit} --id=${cfg.lolminer.nvidia.devices} 2>/dev/null || true; fi'"
            ];
            ExecStart = "${pkgs.steam-run}/bin/steam-run ${lolminerWrapper}/bin/lolminer-wrapper --algo ${cfg.lolminer.algorithm} --pool ${cfg.lolminer.pool} --user ${cfg.lolminer.wallet} --devices ${cfg.lolminer.nvidia.devices} --apiport ${toString cfg.lolminer.nvidia.apiPort} --mode b --tls 1";
            ExecStopPost = "${pkgs.bash}/bin/bash -c '${config.hardware.nvidia.package}/bin/nvidia-smi -pl 250 --id=${cfg.lolminer.nvidia.devices} 2>/dev/null || true'";
            Restart = "on-failure";
            RestartSec = "60s";
            # GPU mining requires device access and privileges
            NoNewPrivileges = false;
            PrivateTmp = true;
            PrivateDevices = false; # Need access to GPU devices
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ProtectHostname = true;
            RestrictRealtime = true;
            ReadOnlyPaths = "/";
            ReadWritePaths = ["/var/lib/mining" "/var/log/mining"];
            LimitMEMLOCK = "4G";
            # Memory limits to prevent OOM
            MemoryMax = "4G";
            MemoryHigh = "3G";
            # Remove all capabilities - use only what's granted
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
          };
        };

        lolminer-amd = mkIf cfg.lolminer.amd.enable {
          description = "lolMiner AMD Mining Service";
          wantedBy = ["multi-user.target"];
          after = ["NetworkManager.service"];

          serviceConfig = {
            User = cfg.user;
            Group = "mining";
            Slice = "mining.slice";
            ExecStartPre = [
              # Set AMD power limit for all GPUs
              "${pkgs.rocm-smi}/bin/rocm-smi --setpoweroverdrive ${toString cfg.lolminer.amd.powerLimit} 2>/dev/null || true"
            ];
            ExecStart = "${pkgs.steam-run}/bin/steam-run ${lolminerAmdWrapper}/bin/lolminer-amd-wrapper --algo ${cfg.lolminer.algorithm} --pool ${cfg.lolminer.pool} --user ${cfg.lolminer.wallet} --devices ${cfg.lolminer.amd.devices} --apiport ${toString cfg.lolminer.amd.apiPort} --api-address 127.0.0.1 --mode b --tls 1";
            Restart = "always";
            RestartSec = "30s";
            Environment = [
              "GPU_MAX_HEAP_SIZE=100"
              "GPU_MAX_ALLOC_PERCENT=100"
              "HSA_OVERRIDE_GFX_VERSION=10.3.0"
            ];
            # Security hardening
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ProtectHostname = true;
            RestrictRealtime = true;
            ReadOnlyPaths = "/";
            ReadWritePaths = ["/var/lib/mining" "/var/log/mining"];
            LimitMEMLOCK = "4G";
            # Remove all capabilities
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
          };
        };

        xmrig = mkIf cfg.xmrig.enable {
          description = "XMRig CPU Mining Service";
          wantedBy = ["multi-user.target"];
          after = ["NetworkManager.service"];

          serviceConfig = {
            User = cfg.user;
            Group = "mining";
            Slice = "mining.slice";
            ExecStart = "${pkgs.xmrig}/bin/xmrig -o stratum+ssl://xtm-rx-us.kryptex.network:8038 -u ${cfg.xmrig.wallet} -t ${toString cfg.xmrig.threads} --http-port 8081 --http-access-token-file ${cfg.xmrig.httpTokenFile} --randomx-1gb-pages --randomx-mode=fast --asm=auto";
            Restart = "always";
            # Security hardening - strict sandboxing
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            RestrictRealtime = true;
            ReadOnlyPaths = "/";
            ReadWritePaths = ["/var/lib/mining" "/var/log/mining"];
            LimitMEMLOCK = "4G";
            # No capabilities - just regular user
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
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

        # System watchdog - reboots if system becomes unresponsive
        nexus-watchdog = {
          description = "System Watchdog for Nexus Stability";
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.bash}/bin/bash -c 'while true; do load=\$(cat /proc/loadavg | awk \"{print \$1}\" | cut -d. -f1); if [ \"\$load\" -gt 20 ]; then sleep 120; load2=\$(cat /proc/loadavg | awk \"{print \$1}\" | cut -d. -f1); if [ \"\$load2\" -gt 20 ]; then echo \"High load persists, rebooting...\"; /run/current-system/sw/bin/reboot; fi; fi; sleep 60; done'";
            Restart = "always";
            RestartSec = "10s";
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

    # Firewall: Only allow mining API ports from localhost
    networking.firewall.interfaces.lo.allowedTCPPorts = [
      cfg.lolminer.nvidia.apiPort
      cfg.lolminer.amd.apiPort
      8081 # XMRig HTTP API
    ];
  };
}
