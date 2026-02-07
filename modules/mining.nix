{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.mining;
  hostname = config.networking.hostName;

  lolminerWrapper = pkgs.writeShellScriptBin "lolminer-wrapper" ''
    #!/usr/bin/env bash
    exec ${pkgs.lolminer}/bin/lolMiner "$@"
  '';

  lolminerAmdWrapper = pkgs.writeShellScriptBin "lolminer-amd-wrapper" ''
    #!/usr/bin/env bash
    exec ${pkgs.lolminer}/bin/lolMiner "$@"
  '';

  defaultWallet = "krxXVNVMM7.${hostname}";
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

    environment.systemPackages = [lolminerWrapper];

    systemd.tmpfiles.rules = [
      "d /var/lib/mining 0750 ${cfg.user} mining - -"
      "d /var/log/mining 0750 ${cfg.user} mining - -"
    ];

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
        nexus-watchdog = {
          description = "System Watchdog for Stability";
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.bash}/bin/bash -c 'while true; do load=$(cat /proc/loadavg | awk \"{print \\$1}\" | cut -d. -f1); if [ \"$load\" -gt 20 ]; then sleep 120; load2=$(cat /proc/loadavg | awk \"{print \\$1}\" | cut -d. -f1); if [ \"$load2\" -gt 20 ]; then echo \"High load persists, rebooting...\"; /run/current-system/sw/bin/reboot; fi; fi; sleep 60; done'";
            Restart = "always";
            RestartSec = "10s";
          };
        };

        lolminer-nvidia = mkIf cfg.lolminer.nvidia.enable {
          description = "lolMiner NVIDIA Mining Service";
          wantedBy = ["multi-user.target"];
          after = ["network.target"];
          serviceConfig = {
            User = cfg.user;
            Group = "mining";
            Slice = "mining.slice";
            ExecStartPre = pkgs.writeShellScript "nvidia-powerlimit-pre" ''
              #!/${pkgs.bash}/bin/bash
              PATH=/run/current-system/sw/bin:$PATH
              nvidia-smi -pm 1 || true
              nvidia-smi -pl ${toString cfg.lolminer.nvidia.powerLimit} || true
            '';
            ExecStart = pkgs.writeShellScript "lolminer-start" ''
              #!/${pkgs.bash}/bin/bash
              export LD_LIBRARY_PATH=/run/opengl-driver/lib:$LD_LIBRARY_PATH
              export CUDA_PATH=/run/opengl-driver
              export NVIDIA_DRIVER_CAPABILITIES=all
              exec ${pkgs.lolminer}/bin/lolMiner \
                --algo ${cfg.lolminer.algorithm} \
                --pool ${cfg.lolminer.pool} \
                --user ${cfg.lolminer.wallet} \
                --devices ${cfg.lolminer.nvidia.devices} \
                --apiport ${toString cfg.lolminer.nvidia.apiPort} \
                --mode n \
                --tls 1
            '';
            Restart = "always";
            RestartSec = "30s";
            Environment = [
              "GPU_MAX_HEAP_SIZE=100"
              "GPU_MAX_ALLOC_PERCENT=100"
            ];
            NoNewPrivileges = false;
            PrivateTmp = false;
            PrivateDevices = false;
            ProtectKernelTunables = false;
            ProtectControlGroups = false;
            ProtectHostname = false;
            RestrictRealtime = false;
            ReadOnlyPaths = [];
            ReadWritePaths = ["/var/lib/mining" "/var/log/mining"];
            LimitMEMLOCK = "4G";
            CapabilityBoundingSet = "CAP_SYS_ADMIN CAP_SYS_NICE";
            AmbientCapabilities = "CAP_SYS_ADMIN CAP_SYS_NICE";
          };
        };

        lolminer-amd = mkIf cfg.lolminer.amd.enable {
          description = "lolMiner AMD Mining Service";
          wantedBy = ["multi-user.target"];
          after = ["network.target" "amd-gpu-power-mgmt.service"];
          serviceConfig = {
            User = cfg.user;
            Group = "mining";
            Slice = "mining.slice";
            ExecStart = pkgs.writeShellScript "lolminer-amd-start" ''
              #!/${pkgs.bash}/bin/bash
              export LD_LIBRARY_PATH=/opt/rocm/lib:/run/opengl-driver/lib:$LD_LIBRARY_PATH
              export ROC_ENABLE_PRE_VEGA=1
              export HSA_OVERRIDE_GFX_VERSION=10.1.0
              export GPU_MAX_HEAP_SIZE=100
              export GPU_MAX_ALLOC_PERCENT=100
              export GPU_SINGLE_ALLOC_PERCENT=100
              export GPU_FORCE_64BIT_PTR=1
              
              exec ${pkgs.lolminer}/bin/lolMiner \
                --algo ${cfg.lolminer.algorithm} \
                --pool ${cfg.lolminer.pool} \
                --user ${cfg.lolminer.wallet} \
                --devices ${cfg.lolminer.amd.devices} \
                --apiport ${toString cfg.lolminer.amd.apiPort} \
                --mode b \
                --tls 1
            '';
            Restart = "always";
            RestartSec = "30s";
            NoNewPrivileges = false;
            PrivateTmp = false;
            PrivateDevices = false;
            ProtectKernelTunables = false;
            ProtectControlGroups = false;
            ProtectHostname = false;
            RestrictRealtime = false;
            ReadOnlyPaths = [];
            ReadWritePaths = ["/var/lib/mining" "/var/log/mining"];
            LimitMEMLOCK = "8G";
            CapabilityBoundingSet = "CAP_SYS_ADMIN CAP_SYS_NICE";
            AmbientCapabilities = "CAP_SYS_ADMIN CAP_SYS_NICE";
          };
        };

        xmrig = mkIf cfg.xmrig.enable {
          description = "XMRig CPU Mining Service";
          wantedBy = ["multi-user.target"];
          after = ["network.target"];
          serviceConfig = {
            User = cfg.user;
            Group = "mining";
            Slice = "mining.slice";
            ExecStart = "${pkgs.xmrig}/bin/xmrig -o stratum+ssl://xtm-rx-us.kryptex.network:8038 -u ${cfg.xmrig.wallet} -t ${toString cfg.xmrig.threads} --http-port 8081 --http-access-token-file ${cfg.xmrig.httpTokenFile} --randomx-1gb-pages --randomx-mode=fast --asm=auto";
            Restart = "always";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            RestrictRealtime = true;
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
