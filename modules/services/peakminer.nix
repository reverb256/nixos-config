{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.peakminer;
  inherit (lib) mkEnableOption mkOption types mkIf mkBefore;
in {
  options.services.peakminer = {
    enable = mkEnableOption "PeakMiner GPU mining";

    wallet = mkOption {
      type = types.str;
      default = "krxXVNVMM7";
      description = "Kryptex wallet address";
    };

    pools = mkOption {
      type = types.listOf types.str;
      default = ["stratum+tcp://prl-us.kryptex.network:7048"];
      description = "Mining pool URLs (uses auth-translator proxy on Linux)";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = ["--coin" "pearl" "--legacy-auth"];
      description = "Extra arguments passed to all miner instances. --legacy-auth makes peakminer send standard Stratum V1 array authorize (login=[WALLET.WORKER, pass]) which Kryptex pools require for worker-name registration.";
    };

    setPowerLimit = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to set GPU power limits via nvidia-smi -pl in ExecStartPre. Requires systemd to run as root (always true here) AND nvidia persistence mode to be enabled.";
    };

    instances = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Service name suffix (e.g. zephyr-3060ti)";
          };
          wallet = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Wallet override (default: services.peakminer.wallet)";
          };
          pools = mkOption {
            type = types.nullOr (types.listOf types.str);
            default = null;
            description = "Pool override (default: services.peakminer.pools)";
          };
          devices = mkOption {
            type = types.str;
            description = "GPU device selection (e.g. \"0\" or \"0,1\")";
          };
          gpuId = mkOption {
            type = types.int;
            description = "NVIDIA GPU device index for power limit";
          };
          powerLimit = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "GPU power limit in watts (null = no change)";
          };
          tempStop = mkOption {
            type = types.int;
            default = 80;
            description = "GPU temperature stop threshold (°C)";
          };
          fanTarget = mkOption {
            type = types.int;
            default = 65;
            description = "GPU target fan speed (%)";
          };
          fanMin = mkOption {
            type = types.int;
            default = 30;
            description = "GPU minimum fan speed (%)";
          };
          fanMax = mkOption {
            type = types.int;
            default = 100;
            description = "GPU maximum fan speed (%)";
          };
          apiPort = mkOption {
            type = types.port;
            description = "API statistics port";
          };
        };
      });
      default = [];
      description = "List of PeakMiner instances";
    };

    exporterInstances = mkOption {
      type = types.listOf (types.submodule {
        options = {
          instanceName = mkOption {
            type = types.str;
            description = "Miner instance name (matched to instances[].name)";
          };
          apiPort = mkOption {
            type = types.port;
            description = "PeakMiner API port to scrape";
          };
          exporterPort = mkOption {
            type = types.port;
            default = 9101;
            description = "Prometheus metrics exporter listen port";
          };
        };
      });
      default = [];
      description = "List of Prometheus exporter instances to generate";
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.config.packageOverrides = pkgs: {
      peakminer = pkgs.callPackage ../pkgs/peakminer.nix {};
    };

    systemd.services = let
      # Build miner service entries
      minerServices =
        builtins.map (instance: let
          instanceName = "peakminer-${instance.name}";
          instanceWallet =
            if instance.wallet != null
            then instance.wallet
            else cfg.wallet;
          instancePools =
            if instance.pools != null
            then instance.pools
            else cfg.pools;
          poolUrl = builtins.head instancePools;
          powerLimitArgs =
            if instance.powerLimit != null && cfg.setPowerLimit
            then "+${pkgs.bash}/bin/bash -c 'i=0; while ! /run/current-system/sw/bin/nvidia-smi -i ${toString instance.gpuId} -pl ${toString instance.powerLimit}; do i=$((i+1)); if [ \"$i\" -ge 30 ]; then echo \"power limit failed after 30s\"; exit 1; fi; sleep 1; done'"
            else "";
        in {
          name = instanceName;
          value = {
            description = "PeakMiner - ${instance.name} (direct pool, --legacy-auth)";
            wantedBy = ["multi-user.target"];
            after = ["network-online.target"];
            wants = ["network-online.target"];

            serviceConfig = {
              Type = "simple";
              User = "root";
              ExecStartPre = mkIf (instance.powerLimit != null && cfg.setPowerLimit) (mkBefore powerLimitArgs);
              ExecStart = pkgs.writeShellScript instanceName ''
                export CUDA_DEVICE_ORDER=PCI_BUS_ID
                export LD_LIBRARY_PATH=/run/opengl-driver/lib:''${LD_LIBRARY_PATH:-}
                exec ${pkgs.peakminer}/bin/peakminer \
                  ${lib.concatStringsSep " " cfg.extraArgs} \
                  --url ${poolUrl} \
                  --user ${instanceWallet}.${instance.name} \
                  --devices ${instance.devices} \
                  --api-port ${toString instance.apiPort} \
                  --gpu-temp-stop ${toString instance.tempStop} \
                  --gpu-fan-target ${toString instance.fanTarget} \
                  --gpu-fan-min ${toString instance.fanMin} \
                  --gpu-fan-max ${toString instance.fanMax}
              '';
              Restart = "always";
              RestartSec = 10;
            };
          };
        })
        cfg.instances;

      # Build Prometheus exporter service entries
      exporterScript = pkgs.writeScript "peakminer-exporter.py" (builtins.readFile ../../pkgs/peakminer-exporter.py);
      exporterServices =
        builtins.map (exp: let
          serviceName = "peakminer-exporter-${exp.instanceName}";
        in {
          name = serviceName;
          value = {
            description = "PeakMiner Prometheus exporter - ${exp.instanceName}";
            wantedBy = ["multi-user.target"];
            after = ["network-online.target" "peakminer-${exp.instanceName}.service"];

            serviceConfig = {
              Type = "simple";
              User = "root";
              Environment = [
                "PEAKMINER_API_PORT=${toString exp.apiPort}"
                "EXPORTER_PORT=${toString exp.exporterPort}"
                "WORKER_NAME=${exp.instanceName}"
              ];
              ExecStart = "${pkgs.python3}/bin/python3 ${exporterScript}";
              Restart = "always";
              RestartSec = 10;
            };
          };
        })
        cfg.exporterInstances;
    in
      lib.listToAttrs (minerServices ++ exporterServices);
  };
}
