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
    echo "Setting NVIDIA GPU power limit to ${toString cfg.lolminer.nvidia.powerLimit}W..."
    nvidia-smi -pm 1 || true
    nvidia-smi -pl ${toString cfg.lolminer.nvidia.powerLimit} || true
    echo "NVIDIA GPU power limit set successfully"
  '';

  # XMRig wrapper script - reads API token and passes to xmrig
  xmrigWrapperScript = pkgs.writeShellScript "xmrig-wrapper" ''
    PATH=/run/current-system/sw/bin:$PATH
    TOKEN_FILE="${cfg.xmrig.httpTokenFile}"
    RUNTIME_CONFIG="/run/xmrig/config.json"

    # Use runtime config with token if available, otherwise fallback to default config
    CONFIG="''${RUNTIME_CONFIG:-/etc/xmrig/config.json}"

    if [ -r "$CONFIG" ]; then
      exec ${pkgs.xmrig}/bin/xmrig -c "$CONFIG" --randomx-1gb-pages --threads=${toString cfg.xmrig.threads}
    else
      exec ${pkgs.xmrig}/bin/xmrig -c /etc/xmrig/config.json --randomx-1gb-pages --threads=${toString cfg.xmrig.threads}
    fi
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
        autostart = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to automatically start the service at boot. If false, service can be controlled imperatively via systemctl.";
        };
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
        autostart = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to automatically start the service at boot. If false, service can be controlled imperatively via systemctl.";
        };
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
      autostart = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to automatically start the service at boot. If false, service can be controlled imperatively via systemctl.";
      };
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
        default = "/run/agenix/xmrig-api-token";
        description = "Path to the HTTP API token file (managed by agenix)";
      };
    };
  };

  config = mkIf cfg.enable {
    # Create mining user and group
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = "mining";
      extraGroups = ["video" "render"]; # For AMD GPU access via /dev/dri/
    };
    users.groups.mining = {};

    boot.kernel.sysctl = {
      "vm.nr_hugepages" = 1280;
    };

    # Load MSR module for CPU mining performance
    # Required by xmrig for CPU MSR access (RandomX optimization)
    boot.kernelModules = ["msr"];

    # Set permissions on MSR devices for mining user
    # Allows xmrig to access CPU MSRs for performance optimization
    services.udev.extraRules = ''
      KERNEL=="msr", MODE="0660", GROUP="mining"
    '';

    environment.systemPackages = [pkgs.lolminer];

    systemd.tmpfiles.rules = [
      "d /var/lib/mining 0750 ${cfg.user} mining - -"
      "d /var/log/mining 0750 ${cfg.user} mining - -"
      "d /run/xmrig 0750 ${cfg.user} mining - -"
    ];

    environment.etc."xmrig/config.json" = mkIf cfg.xmrig.enable {
      text = builtins.toJSON {
        api = {
          id = null;
          worker-id = null;
        };
        http = {
          enabled = true;
          host = "127.0.0.1";
          port = 8081;
          # restricted: false to allow pause/resume control endpoints
          # Token will be injected at runtime via ExecStartPre
          restricted = false;
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
        # NVIDIA GPU power limit service (runs before lolminer)
        nvidia-gpu-power-limit = mkIf cfg.lolminer.nvidia.enable {
          description = "Set NVIDIA GPU Power Limit for Mining";
          wantedBy = ["multi-user.target"];
          before = ["lolminer-nvidia.service"];
          requiredBy = ["lolminer-nvidia.service"];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = nvidiaGpuPowerLimitScript;
            RemainAfterExit = true;
          };
        };

        lolminer-nvidia = mkIf cfg.lolminer.nvidia.enable {
          description = "lolMiner NVIDIA Mining Service";
          wantedBy = mkIf cfg.lolminer.nvidia.autostart ["multi-user.target"];
          after = [
            "network.target"
            "nvidia-gpu-power-limit.service"
          ];
          requires = ["nvidia-gpu-power-limit.service"];
          serviceConfig =
            {
              User = cfg.user;
              Group = "mining";
              Slice = "mining.slice";
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
          wantedBy = mkIf cfg.lolminer.amd.autostart ["multi-user.target"];
          after = [
            "network.target"
          ];
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
          wantedBy = mkIf cfg.xmrig.autostart ["multi-user.target"];
          after = ["network.target"];
          serviceConfig = {
            User = cfg.user;
            Group = "mining";
            Slice = "mining.slice";
            # Prepare runtime config with API token injected
            ExecStartPre = pkgs.writeShellScript "xmrig-config-prep-v4" ''
              TOKEN_FILE="${cfg.xmrig.httpTokenFile}"
              CONFIG_DIR=/run/xmrig

              if [ -r "$TOKEN_FILE" ]; then
                TOKEN=$(cat "$TOKEN_FILE")
                mkdir -p "$CONFIG_DIR"
                # Inject token into config - double quotes allow shell expansion
                ${pkgs.jq}/bin/jq ".http.\"access-token\" = \"$TOKEN\"" /etc/xmrig/config.json > "$CONFIG_DIR/config.json"
              else
                # Fallback without token
                cp /etc/xmrig/config.json "$CONFIG_DIR/config.json"
              fi
            '';
            # Use wrapper script that uses the runtime config
            ExecStart = xmrigWrapperScript;
            Restart = "always";
            # NoNewPrivileges must be false to allow CAP_SYS_RAWIO for MSR access
            NoNewPrivileges = false;
            PrivateTmp = true;
            # ProtectKernelTunables must be off for MSR device access
            ProtectKernelTunables = false;
            ProtectControlGroups = true;
            ProtectHostname = true;
            RestrictRealtime = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadOnlyPaths = "/";
            ReadWritePaths = [
              "/var/lib/mining"
              "/var/log/mining"
              "/run/xmrig" # Allow writing runtime config
            ];
            LimitMEMLOCK = "4G";
            # Allow MSR access for CPU performance optimization
            # CAP_SYS_RAWIO required for Model-Specific Register access
            CapabilityBoundingSet = "CAP_SYS_RAWIO";
            AmbientCapabilities = "CAP_SYS_RAWIO";
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
