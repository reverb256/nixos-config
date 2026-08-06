{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.krig;
  inherit (lib) mkEnableOption mkOption types mkIf mkBefore;
in {
  options.services.krig = {
    enable = mkEnableOption "Krig (Kryptex PRL) GPU mining";

    wallet = mkOption {
      type = types.str;
      default = "krxXVNVMM7";
      description = "Kryptex PRL payout wallet. Krig sends this as the pool login; the pool worker is the rig hostname (Krig has no --worker flag).";
    };

    pool = mkOption {
      type = types.str;
      # Krig is TLS-only. prl-us.kryptex.network:8048 is the NA SSL endpoint.
      default = "stratum+ssl://prl-us.kryptex.network:8048";
      description = "Kryptex PRL stratum endpoint (stratum+ssl:// required).";
    };

    setPowerLimit = mkOption {
      type = types.bool;
      default = true;
      description = "Set GPU power limits via nvidia-smi -pl in ExecStartPre. Krig has no power/fan/temp flags; use vendor tools + nvidia-smi.";
    };

    instances = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Local instance name (systemd service suffix + exporter label), e.g. zephyr-3060ti.";
          };
          devices = mkOption {
            type = types.str;
            description = "GPU device selection for -d (e.g. \"0\" or \"0,1\").";
          };
          gpuId = mkOption {
            type = types.int;
            description = "NVIDIA GPU index for nvidia-smi power limit.";
          };
          powerLimit = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "GPU power limit in watts (null = no change).";
          };
          apiPort = mkOption {
            type = types.port;
            description = "Krig stats API port (serves native /metrics + /summary).";
          };
          exporterPort = mkOption {
            type = types.port;
            default = 9101;
            description = "Prometheus exporter (proxy) listen port.";
          };
        };
      });
      default = [];
      description = "List of Krig miner instances.";
    };
  };

  config = mkIf cfg.enable {
    # Krig is a single binary auto-detecting CUDA/ROCm. We add it to the
    # package set so `pkgs.krig` resolves to our wrapped derivation.
    nixpkgs.config.packageOverrides = pkgs: {
      krig = pkgs.callPackage ../pkgs/krig.nix {};
    };

    systemd.services = let
      minerServices =
        builtins.map (instance: let
          instanceName = "krig-${instance.name}";
          powerLimitScript = pkgs.writeShellScript "krig-power-limit-${instance.name}" ''
            #!/usr/bin/env bash
            set -e
            i=0
            while ! /run/current-system/sw/bin/nvidia-smi -i ${toString instance.gpuId} -pl ${toString instance.powerLimit}; do
              i=$((i+1))
              if [ "$i" -ge 30 ]; then
                echo "power limit failed after 30s"
                exit 1
              fi
              sleep 1
            done
          '';
          powerLimitArgs =
            if instance.powerLimit != null && cfg.setPowerLimit
            then "+${powerLimitScript}"
            else "";
        in {
          name = instanceName;
          value = {
            description = "Krig (Kryptex PRL) - ${instance.name}";
            wantedBy = ["multi-user.target"];
            after = ["network-online.target"];
            wants = ["network-online.target"];

            serviceConfig = {
              Type = "simple";
              User = "root";
              ExecStartPre = mkIf (instance.powerLimit != null && cfg.setPowerLimit) (mkBefore powerLimitArgs);
              ExecStart = pkgs.writeShellScript instanceName ''
                export CUDA_DEVICE_ORDER=PCI_BUS_ID
                exec ${pkgs.krig}/bin/krig-miner \
                  --url ${cfg.pool} \
                  --user ${cfg.wallet} \
                  --api-port ${toString instance.apiPort} \
                  --api-host 127.0.0.1 \
                  --devices ${instance.devices}
              '';
              Restart = "always";
              RestartSec = 10;
            };
          };
        })
        cfg.instances;

      exporterScript = pkgs.writeScript "krig-exporter.py" (builtins.readFile ../../pkgs/krig-exporter.py);
      exporterServices =
        builtins.map (instance: let
          serviceName = "krig-exporter-${instance.name}";
        in {
          name = serviceName;
          value = {
            description = "Krig Prometheus exporter (proxy) - ${instance.name}";
            wantedBy = ["multi-user.target"];
            after = ["network-online.target" "krig-${instance.name}.service"];
            wants = ["network-online.target"];
            requires = ["krig-${instance.name}.service"];

            serviceConfig = {
              Type = "simple";
              User = "root";
              Environment = [
                "KRIG_API_PORT=${toString instance.apiPort}"
                "EXPORTER_PORT=${toString instance.exporterPort}"
                "WORKER_NAME=${instance.name}"
              ];
              ExecStart = "${pkgs.python3}/bin/python3 ${exporterScript}";
              Restart = "always";
              RestartSec = 10;
            };
          };
        })
        cfg.instances;
    in
      lib.listToAttrs (minerServices ++ exporterServices);
  };
}
