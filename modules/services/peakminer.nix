{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.peakminer;
  inherit (lib) mkEnableOption mkOption types mkIf mkBefore;

  # Resolve a GPU product-name substring to its current CUDA index and UUID.
  # Prints "INDEX UUID" on the single matching line, or nothing if absent.
  # Robust to enumeration reorder: never keys on a fixed index.
  resolveGpu = pkgs.writeShellScript "peakminer-resolve-gpu" ''
    set -euo pipefail
    want="$1"
    /run/current-system/sw/bin/nvidia-smi --query-gpu=index,uuid,name \
      --format=csv,noheader,nounits 2>/dev/null | while IFS=', ' read -r idx uuid name; do
      if [[ "$name" == *"$want"* ]]; then
        echo "$idx $uuid"
        exit 0
      fi
    done
    exit 1
  '';
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
          # GPU is selected by PRODUCT NAME (e.g. "RTX 3090", "RTX 3060 Ti"),
          # NOT by index. Index assignment is unstable across reboots / when a
          # second GPU is VFIO-blacklisted, which previously caused one GPU's
          # power limit to bleed onto the other. We resolve name -> UUID/index
          # at runtime so the setting always lands on the right physical card.
          gpuName = mkOption {
            type = types.str;
            description = "NVIDIA product name substring to match (e.g. \"RTX 3090\"). Used to resolve the real GPU, not the enumeration index.";
          };
          devices = mkOption {
            type = types.str;
            description = "PeakMiner CUDA device list, e.g. 0 or 0,1 (resolved at runtime from gpuName)";
          };
          gpuId = mkOption {
            type = types.int;
            description = "DEPRECATED index-based selector — kept for compat but ignored; gpuName is used instead.";
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
        export PATH="${pkgs.gawk}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.findutils}/bin:${pkgs.systemd}/bin:''${PATH:-}"
        for attempt in $(seq 1 30); do
          resolved=$(${resolveGpu} "${instance.gpuName}" || true)
          if [ -z "$resolved" ]; then
            echo "PeakMiner: GPU '${instance.gpuName}' not present, skipping power limit" >&2
            exit 0
          fi
          uuid=$(echo "$resolved" | ${pkgs.gawk}/bin/awk '{print $2}')
          if /run/current-system/sw/bin/nvidia-smi \
              -i "$uuid" \
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

        # Resolve the real CUDA index for this GPU by NAME (not hardcoded index),
        # so a VFIO-blacklist / reboot that reorders GPUs can't put the wrong
        # card into this miner instance.
        resolved=$(${resolveGpu} "${instance.gpuName}" || true)
        if [ -z "$resolved" ]; then
          echo "PeakMiner ${instance.name}: GPU '${instance.gpuName}' not present; exiting" >&2
          exit 1
        fi
        cuda_idx=$(echo "$resolved" | ${pkgs.gawk}/bin/awk '{print $1}')
        echo "PeakMiner ${instance.name}: targeting CUDA index $cuda_idx (${instance.gpuName})" >&2

        while true; do
          for pool in "''${pools[@]}"; do
            echo "PeakMiner ${instance.name}: starting $pool" >&2
            ${pkgs.peakminer}/bin/peakminer \
              --url "$pool" \
              --user "$wallet" \
              --password "$password" \
              --coin pearl \
              --devices "$cuda_idx" \
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
