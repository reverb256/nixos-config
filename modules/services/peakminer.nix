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
      default = ["--coin" "pearl"];
      description = "Extra arguments passed to all miner instances";
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
          proxyPort = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "Auth-translator proxy port (null = direct pool connection)";
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
          poolUrl =
            if instance.proxyPort != null
            then "stratum+tcp://127.0.0.1:${toString instance.proxyPort}"
            else builtins.head instancePools;
          powerLimitArgs =
            if instance.powerLimit != null
            then "+/run/current-system/sw/bin/nvidia-smi -i ${toString instance.gpuId} -pl ${toString instance.powerLimit}"
            else "";
          proxyService =
            if instance.proxyPort != null
            then ["peakminer-proxy-${instance.name}.service"]
            else [];
        in {
          name = instanceName;
          value = {
            description = "PeakMiner - ${instance.name}";
            wantedBy = ["multi-user.target"];
            after = ["network-online.target"] ++ proxyService;
            wants = ["network-online.target"];
            requires = proxyService;

            serviceConfig = {
              Type = "simple";
              User = "root";
              ExecStartPre = mkIf (instance.powerLimit != null) (mkBefore powerLimitArgs);
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

      # Build proxy service entries
      # lib.optionalAttrs returns {} when condition is false; filter those out
      # using s ? name (empty attrsets have no 'name' attribute)
      proxyServices = builtins.filter (s: s ? name) (
        builtins.map (instance: let
          proxyServiceName = "peakminer-proxy-${instance.name}";
          instanceWallet =
            if instance.wallet != null
            then instance.wallet
            else cfg.wallet;
          instancePools =
            if instance.pools != null
            then instance.pools
            else cfg.pools;
        in
          lib.optionalAttrs (instance.proxyPort != null) {
            name = proxyServiceName;
            value = {
              description = "PeakMiner auth-translator proxy - ${instance.name}";
              wantedBy = ["multi-user.target"];
              after = ["network-online.target"];

              serviceConfig = {
                Type = "simple";
                User = "root";
                ExecStart = pkgs.writeShellScript proxyServiceName ''
                  ${pkgs.peakminer}/bin/peakminer-proxy \
                    --listen-host 127.0.0.1 \
                    --listen-port ${toString instance.proxyPort} \
                    --target ${builtins.head instancePools} \
                    --wallet ${instanceWallet} \
                    --worker ${instance.name}
                '';
                Restart = "always";
                RestartSec = 10;
              };
            };
          })
        cfg.instances
      );

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
      lib.listToAttrs (minerServices ++ proxyServices ++ exporterServices);
  };
}
