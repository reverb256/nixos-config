{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.srbminer = {
    enable = lib.mkEnableOption "SRBMiner-Multi GPU mining";

    instances = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Service name suffix";
          };
          gpuId = lib.mkOption {
            type = lib.types.int;
            description = "GPU ID to use";
          };
          wallet = lib.mkOption {
            type = lib.types.str;
            description = "Wallet address";
          };
          pool = lib.mkOption {
            type = lib.types.str;
            default = "stratum+ssl://prl-us.kryptex.network:8048";
            description = "Mining pool URL";
          };
          apiPort = lib.mkOption {
            type = lib.types.int;
            default = 21550;
            description = "API port";
          };
          powerLimit = lib.mkOption {
            type = lib.types.int;
            default = 100;
            description = "Power limit in watts";
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
  };

  config = lib.mkIf config.services.srbminer.enable {
    systemd.tmpfiles.rules = [
      "d /data/SRBMiner-MULTI 0755 j_kro j_kro - -"
      "C! /data/SRBMiner-MULTI/SRBMiner-MULTI 0755 j_kro j_kro - /home/j_kro/SRBMiner-MULTI"
    ];

    systemd.services = lib.listToAttrs (
      builtins.map (instance: {
        name = "srbminer-${instance.name}";
        value = {
          description = "SRBMiner-Multi - ${instance.name}";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target"];

          serviceConfig = {
            Type = "simple";
            User = config.services.srbminer.user;
            Environment = [
              "LD_LIBRARY_PATH=/run/opengl-driver/lib"
              "CUDA_VISIBLE_DEVICES=${toString instance.gpuId}"
            ];
            ExecStartPre = "${config.hardware.nvidia.package}/bin/nvidia-smi -i ${toString instance.gpuId} -pl ${toString instance.powerLimit}";
            ExecStart = "${pkgs.writeShellScriptBin "srbminer-${instance.name}" ''
              /home/j_kro/SRBMiner-MULTI \
                --disable-cpu \
                --disable-gpu-amd \
                --algorithm pearlhash \
                --pool ${instance.pool} \
                --wallet ${instance.wallet} \
                --gpu-id 0 \
                --tls true \
                --api-enable \
                --api-port ${toString instance.apiPort}
            ''}/bin/srbminer-${instance.name}";
            Restart = "always";
            RestartSec = "10";
          };
        };
      }) config.services.srbminer.instances
    );
  };
}
