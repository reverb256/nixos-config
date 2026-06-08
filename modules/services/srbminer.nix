{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.srbminer;
  defaultBinary = "/home/j_kro/SRBMiner-MULTI";

  # Resolve pool/algorithm - use GPU override if non-null, otherwise global
  resolvePool = gpu: if gpu.pool != null then gpu.pool else cfg.pool;
  resolveAlgo = gpu: if gpu.algorithm != null then gpu.algorithm else cfg.algorithm;
in {
  options.services.srbminer = {
    enable = lib.mkEnableOption "SRBMiner-MULTI GPU miners";

    binary = lib.mkOption {
      type = lib.types.path;
      default = defaultBinary;
      description = "Path to SRBMiner-MULTI binary";
    };

    pool = lib.mkOption {
      type = lib.types.str;
      default = "stratum+ssl://prl-us.kryptex.network:8048";
      description = "Mining pool URL";
    };

    wallet = lib.mkOption {
      type = lib.types.str;
      default = "krxXVNVMM7";
      description = "Base wallet address";
    };

    algorithm = lib.mkOption {
      type = lib.types.str;
      default = "pearlhash";
      description = "Mining algorithm";
    };

    tls = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable TLS for pool connection";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--disable-cpu" "--disable-gpu-amd" ];
      description = "Common extra arguments for all miners";
    };

    restart = lib.mkOption {
      type = lib.types.str;
      default = "always";
      description = "Systemd Restart policy";
    };
    restartSec = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Systemd RestartSec in seconds";
    };

    gpu0 = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "Enable GPU 0 miner";
          apiPort = lib.mkOption {
            type = lib.types.port;
            default = 21550;
          };
          workerSuffix = lib.mkOption {
            type = lib.types.str;
            default = "forge-4060-0";
          };
          pool = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          algorithm = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          extraArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
      };
      default = { enable = true; };
    };

    gpu1 = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "Enable GPU 1 miner";
          apiPort = lib.mkOption {
            type = lib.types.port;
            default = 21551;
          };
          workerSuffix = lib.mkOption {
            type = lib.types.str;
            default = "forge-4060-1";
          };
          pool = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          algorithm = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          extraArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
      };
      default = { enable = true; };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = {
      srbminer-gpu0 = lib.mkIf cfg.gpu0.enable {
        description = "SRBMiner-MULTI GPU 0";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = lib.getExe cfg.binary + " --pool ${resolvePool cfg.gpu0} --wallet ${cfg.wallet}.${cfg.gpu0.workerSuffix} --algorithm ${resolveAlgo cfg.gpu0} ${lib.concatStringsSep " " (cfg.extraArgs ++ cfg.gpu0.extraArgs)}";
          Restart = cfg.restart;
          RestartSec = cfg.restartSec;
        };
      };
      srbminer-gpu1 = lib.mkIf cfg.gpu1.enable {
        description = "SRBMiner-MULTI GPU 1";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = lib.getExe cfg.binary + " --pool ${resolvePool cfg.gpu1} --wallet ${cfg.wallet}.${cfg.gpu1.workerSuffix} --algorithm ${resolveAlgo cfg.gpu1} ${lib.concatStringsSep " " (cfg.extraArgs ++ cfg.gpu1.extraArgs)}";
          Restart = cfg.restart;
          RestartSec = cfg.restartSec;
        };
      };
    };
  };
}
