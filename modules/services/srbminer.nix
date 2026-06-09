{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.srbminer;

  resolvePool = inst: if inst.pool != null then inst.pool else cfg.pool;
  resolveAlgo = inst: if inst.algorithm != null then inst.algorithm else cfg.algorithm;

  defaultBinary = pkgs.fetchzip {
    name = "SRBMiner-Multi-${cfg.version}";
    url = "https://github.com/doktor83/SRBMiner-Multi/releases/download/${cfg.version}/srbminer_custom-${cfg.version}.tar.gz";
    hash = cfg.sha256;
    stripRoot = true;
    extraPostFetch = ''
      mv $out/srbminer_custom_bin $out/SRBMiner-MULTI
    '';
  } + "/SRBMiner-MULTI";

in {
  options.services.srbminer = {
    enable = lib.mkEnableOption "SRBMiner-MULTI GPU mining";

    version = lib.mkOption {
      type = lib.types.str;
      default = "3.3.6";
      description = "SRBMiner version tag";
    };

    sha256 = lib.mkOption {
      type = lib.types.str;
      default = "sha256-b960e1a2ab29bb4b20bb5ce89d704a00f69a18a487de93ec5f1d145b54f79e71";
      description = "SHA-256 hash of the SRBMiner tarball.";
    };

    binary = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to SRBMiner-MULTI binary. If null, fetches from GitHub releases.";
    };

    pool = lib.mkOption {
      type = lib.types.str;
      default = "stratum+ssl://prl-us.kryptex.network:8048";
      description = "Default mining pool URL";
    };

    algorithm = lib.mkOption {
      type = lib.types.str;
      default = "pearlhash";
      description = "Default mining algorithm";
    };

    tls = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable TLS for pool connection";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--disable-cpu" "--disable-gpu-amd" ];
      description = "Extra arguments passed to all miner instances";
    };

    instances = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Service name suffix (e.g. 4060-0)";
          };
          gpuId = lib.mkOption {
            type = lib.types.int;
            description = "NVIDIA GPU device index";
          };
          wallet = lib.mkOption {
            type = lib.types.str;
            description = "Mining wallet with worker suffix";
          };
          pool = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Per-instance pool override";
          };
          algorithm = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Per-instance algorithm override";
          };
          apiPort = lib.mkOption {
            type = lib.types.port;
            default = 21550;
            description = "API statistics port";
          };
          powerLimit = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "GPU power limit in watts (null = no change)";
          };
          extraArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Per-instance extra arguments";
          };
        };
      });
      default = [];
      description = "List of SRBMiner instances";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User to run miner as";
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
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.listToAttrs (
      builtins.map (instance: let
        binaryPath = if cfg.binary != null then cfg.binary else defaultBinary;
        tlsFlag = if cfg.tls then "--tls true" else "--tls false";
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
            ExecStartPre = lib.mkIf (instance.powerLimit != null) (
              lib.mkBefore powerLimitArgs
            );
            ExecStart = pkgs.writeShellScript "srbminer-${instance.name}" ''
              export CUDA_DEVICE_ORDER=PCI_BUS_ID
              export CUDA_VISIBLE_DEVICES=${toString instance.gpuId}
              export LD_LIBRARY_PATH=/run/opengl-driver/lib
              exec ${binaryPath} \
                ${toString cfg.extraArgs} \
                ${toString instance.extraArgs} \
                --algorithm ${resolveAlgo instance} \
                --pool ${resolvePool instance} \
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
