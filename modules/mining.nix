{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.mining;

  # Get NVIDIA paths from kernel
  nvidiaStable = pkgs.linuxPackages_zen.nvidiaPackages.stable;
  nvidiaLibPath = "${nvidiaStable}/lib";
  nvidiaSmipath = "${nvidiaStable.bin}/bin/nvidia-smi";

  # Wrapper for NVIDIA OpenCL inside steam-run
  lolminerWrapper = pkgs.writeShellScriptBin "lolminer-wrapper" ''
    #!/usr/bin/env bash
    NVIDIA_OPENCL="${nvidiaLibPath}/libnvidia-opencl.so"
    # Use writable location for OpenCL vendor files to avoid permission issues
    mkdir -p /tmp/opencl-vendors
    echo "''${NVIDIA_OPENCL}" > /tmp/opencl-vendors/nvidia.icd
    export OCL_ICD_VENDORS=/tmp/opencl-vendors
    export LD_LIBRARY_PATH="${nvidiaLibPath}:/run/opengl-driver/lib:$LD_LIBRARY_PATH"
    export GPU_MAX_HEAP_SIZE=100
    export GPU_MAX_ALLOC_PERCENT=100
    exec ${pkgs.lolminer}/bin/lolMiner "$@"
  '';

  # Wrapper for AMD OpenCL inside steam-run
  lolminerAmdWrapper = pkgs.writeShellScriptBin "lolminer-amd-wrapper" ''
    #!/usr/bin/env bash
    # Set up ROCm/OpenCL for AMD GPUs inside steam-run
    mkdir -p /etc/OpenCL/vendors
    echo "/run/opengl-driver/lib/libamdocl-orca64.so" > /etc/OpenCL/vendors/amdocl64.icd 2>/dev/null || true
    echo "/run/opengl-driver/lib/libamdocl64.so" > /etc/OpenCL/vendors/amdocl64.icd 2>/dev/null || true
    export LD_LIBRARY_PATH="/run/opengl-driver/lib:/opt/rocm/hip/lib:/opt/rocm/lib:$LD_LIBRARY_PATH"
    export ROCM_PATH=/opt/rocm
    export HSA_OVERRIDE_GFX_VERSION=10.3.0
    export GPU_MAX_HEAP_SIZE=100
    export GPU_MAX_ALLOC_PERCENT=100
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
      httpToken = mkOption {
        type = types.str;
        default = "my-secret-token";
      };
    };
  };

  config = mkIf cfg.enable {
    boot.kernel.sysctl = {
      "vm.nr_hugepages" = 1280;
    };

    environment.systemPackages = [monitorScript lolminerWrapper];

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
          "access-token" = cfg.xmrig.httpToken or "my-secret-token";
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
          after = ["NetworkManager.service" "nvidia-persistenced.service"];

          serviceConfig = {
            User = "root";
            Group = "mining";
            Slice = "mining.slice";
            ExecStartPre = [
              "${pkgs.bash}/bin/bash -c '${nvidiaSmipath} -pm 1 || true'"
              "${pkgs.bash}/bin/bash -c '${nvidiaSmipath} -pl ${toString cfg.lolminer.nvidia.powerLimit} || true'"
            ];
            ExecStart = "${pkgs.steam-run}/bin/steam-run ${lolminerWrapper}/bin/lolminer-wrapper --algo ${cfg.lolminer.algorithm} --pool ${cfg.lolminer.pool} --user ${cfg.lolminer.wallet} --devices ${cfg.lolminer.nvidia.devices} --apiport ${toString cfg.lolminer.nvidia.apiPort} --mode b --tls 1";
            ExecStopPost = "${pkgs.bash}/bin/bash -c '${nvidiaSmipath} -pl 350 || true'";
            Restart = "always";
            RestartSec = "30s";
            Environment = ["PATH=/run/current-system/sw/bin:$PATH"];
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
            User = "root";
            Group = "mining";
            Slice = "mining.slice";
            ExecStart = "${pkgs.steam-run}/bin/steam-run ${lolminerAmdWrapper}/bin/lolminer-amd-wrapper --algo ${cfg.lolminer.algorithm} --pool ${cfg.lolminer.pool} --user ${cfg.lolminer.wallet} --devices ${cfg.lolminer.amd.devices} --apiport ${toString cfg.lolminer.amd.apiPort} --mode b --tls 1";
            Restart = "always";
            RestartSec = "30s";
            Environment = [
              "PATH=/run/current-system/sw/bin:$PATH"
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
            ExecStart = "${pkgs.xmrig}/bin/xmrig -o stratum+ssl://xtm-rx-us.kryptex.network:8038 -u ${cfg.xmrig.wallet} -t ${toString cfg.xmrig.threads} --http-port 8081 --http-access-token ${cfg.xmrig.httpToken} --randomx-1gb-pages --randomx-mode=fast --asm=auto";
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
