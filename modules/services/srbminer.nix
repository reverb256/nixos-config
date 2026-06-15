{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.srbminer;
  inherit (lib) mkEnableOption mkOption types mkIf mkBefore;
in {
  options.services.srbminer = {
    enable = mkEnableOption "SRBMiner-MULTI GPU mining";

    pool = mkOption {
      type = types.str;
      default = "stratum+ssl://prl-us.kryptex.network:8048";
      description = "Default mining pool URL";
    };

    algorithm = mkOption {
      type = types.str;
      default = "pearlhash";
      description = "Default mining algorithm";
    };

    tls = mkOption {
      type = types.bool;
      default = true;
      description = "Enable TLS for pool connection";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ "--disable-cpu" "--disable-gpu-amd" ];
      description = "Extra arguments passed to all miner instances";
    };

    instances = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Service name suffix (e.g. zephyr-3060ti)";
          };
          gpuId = mkOption {
            type = types.int;
            description = "NVIDIA GPU device index";
          };
          wallet = mkOption {
            type = types.str;
            description = "Mining wallet with worker suffix";
          };
          pool = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Per-instance pool override";
          };
          algorithm = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Per-instance algorithm override";
          };
          apiPort = mkOption {
            type = types.port;
            default = 21550;
            description = "API statistics port";
          };
          powerLimit = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "GPU power limit in watts (null = no change)";
          };
          extraArgs = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Per-instance extra arguments";
          };
        };
      });
      default = [];
      description = "List of SRBMiner instances";
    };

    user = mkOption {
      type = types.str;
      default = "j_kro";
      description = "User to run miner as";
    };

    restart = mkOption {
      type = types.str;
      default = "always";
      description = "Systemd Restart policy";
    };
    restartSec = mkOption {
      type = types.int;
      default = 10;
      description = "Systemd RestartSec in seconds";
    };
  };

  config = mkIf cfg.enable {
    systemd.services = lib.listToAttrs (
      builtins.map (instance: let
        srbminerBin = "${pkgs.srbminer-multi}/bin/SRBMiner-MULTI";
        tlsFlag = if cfg.tls then "--tls true" else "--tls false";
        poolUrl = if instance.pool != null then instance.pool else cfg.pool;
        algo = if instance.algorithm != null then instance.algorithm else cfg.algorithm;
        powerLimitArgs = if instance.powerLimit != null then
          "+/run/current-system/sw/bin/nvidia-smi -i ${toString instance.gpuId} -pl ${toString instance.powerLimit}"
        else "";
      in {
        name = "srbminer-${instance.name}";
        value = {
          description = "SRBMiner-Multi - ${instance.name} (GPU ${toString instance.gpuId})";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            ExecStartPre = mkIf (instance.powerLimit != null) (
              mkBefore powerLimitArgs
            );
            ExecStart = pkgs.writeShellScript "srbminer-${instance.name}" ''
              export CUDA_DEVICE_ORDER=PCI_BUS_ID
              export CUDA_VISIBLE_DEVICES=${toString instance.gpuId}
              export LD_LIBRARY_PATH=/run/opengl-driver/lib
              exec ${srbminerBin} \
                ${toString cfg.extraArgs} \
                ${toString instance.extraArgs} \
                --algorithm ${algo} \
                --pool ${poolUrl} \
                --wallet ${instance.wallet} \
                --gpu-id 0 \
                ${tlsFlag} \
                --api-enable \
                --api-port ${toString instance.apiPort}
            '';
            Restart = cfg.restart;
            RestartSec = cfg.restartSec;
          };
        };
      }) cfg.instances
    );
  };
}
