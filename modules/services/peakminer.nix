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
      description = "Kryptex payout wallet address";
    };

    password = mkOption {
      type = types.str;
      default = "x";
      description = "Kryptex pool password";
    };

    pools = mkOption {
      type = types.listOf types.str;
      default = [
        "stratum+tcp://prl-us.kryptex.network:7048"
        "stratum+tcp://prl.kryptex.network:7048"
      ];
      description = "Kryptex plain TCP pool endpoints, tried in order";
    };

    setPowerLimit = mkOption {
      type = types.bool;
      default = true;
      description = "Set NVIDIA GPU power limits before starting PeakMiner";
    };

    instances = mkOption {
      type = types.listOf (types.submodule ({...}: {
        options = {
          name = mkOption {
            type = types.str;
            description = "Service name suffix and worker name";
          };
          devices = mkOption {
            type = types.str;
            description = "PeakMiner CUDA device list, e.g. 0 or 0,1";
          };
          gpuId = mkOption {
            type = types.int;
            description = "NVIDIA GPU index used for the power limit";
          };
          powerLimit = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "NVIDIA GPU power limit in watts";
          };
          apiPort = mkOption {
            type = types.port;
            description = "PeakMiner localhost stats API port (/summary)";
          };
          extraArgs = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Additional PeakMiner arguments";
          };
        };
      }));
      default = [];
      description = "PeakMiner instances";
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [
      (_final: prev: {
        peakminer = prev.callPackage ../../pkgs/peakminer.nix {};
      })
    ];

    systemd.services = lib.listToAttrs (builtins.map (instance: let
      serviceName = "peakminer-${instance.name}";
      powerLimitScript = pkgs.writeShellScript "peakminer-power-limit-${instance.name}" ''
        set -euo pipefail
        for attempt in $(seq 1 30); do
          if /run/current-system/sw/bin/nvidia-smi \
              -i ${toString instance.gpuId} \
              -pl ${toString instance.powerLimit}; then
            exit 0
          fi
          sleep 1
        done
        echo "PeakMiner: power limit failed after 30 seconds" >&2
        exit 1
      '';
      peakminerScript = pkgs.writeShellScript serviceName ''
        set -euo pipefail
        export CUDA_DEVICE_ORDER=PCI_BUS_ID
        export LD_LIBRARY_PATH=/run/opengl-driver/lib:''${LD_LIBRARY_PATH:-}

        wallet="${cfg.wallet}/${instance.name}"
        password=${lib.escapeShellArg cfg.password}
        pools=(${lib.concatStringsSep " " (map (pool: lib.escapeShellArg pool) cfg.pools)})

        while true; do
          for pool in "''${pools[@]}"; do
            echo "PeakMiner ${instance.name}: starting $pool" >&2
            ${pkgs.peakminer}/bin/peakminer \
              --url "$pool" \
              --user "$wallet" \
              --password "$password" \
              --coin pearl \
              --devices ${lib.escapeShellArg instance.devices} \
              --api-port ${toString instance.apiPort} \
              ${lib.concatStringsSep " " (map lib.escapeShellArg instance.extraArgs)}
            echo "PeakMiner ${instance.name}: pool exited; trying next pool" >&2
          done
          sleep 5
        done
      '';
    in {
      name = serviceName;
      value = {
        description = "PeakMiner GPU miner - ${instance.name}";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Type = "simple";
          User = "root";
          ExecStartPre = mkIf (instance.powerLimit != null && cfg.setPowerLimit) (
            mkBefore "+${powerLimitScript}"
          );
          ExecStart = peakminerScript;
          Restart = "always";
          RestartSec = 10;
        };
      };
    }) cfg.instances);
  };
}
