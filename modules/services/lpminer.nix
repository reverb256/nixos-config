{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.lpminer = {
    enable = lib.mkEnableOption "lpminer GPU mining";

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
          powerLimit = lib.mkOption {
            type = lib.types.int;
            default = 100;
            description = "Power limit in watts";
          };
        };
      });
      default = [];
      description = "List of lpminer instances";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User to run miner as";
    };
  };

  config = lib.mkIf config.services.lpminer.enable {
    systemd.tmpfiles.rules = [
      "d /data/lpminer 0755 j_kro j_kro - -"
      "C! /data/lpminer/lpminer 0755 j_kro j_kro - /data/lpminer/lpminer"
    ];

    systemd.services = lib.listToAttrs (
      builtins.map (instance: {
        name = "lpminer-${instance.name}";
        value = {
          description = "lpminer - ${instance.name}";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target"];

          serviceConfig = {
            Type = "simple";
            User = config.services.lpminer.user;
            Environment = [
              "LD_LIBRARY_PATH=/run/opengl-driver/lib"
              "CUDA_VISIBLE_DEVICES=${toString instance.gpuId}"
            ];
            ExecStartPre = "${config.hardware.nvidia.package}/bin/nvidia-smi -i ${toString instance.gpuId} -pl ${toString instance.powerLimit}";
            ExecStart = "${pkgs.writeShellScriptBin "lpminer-${instance.name}" ''
              /data/lpminer/lpminer \
                --algo pearlhash \
                --pool ${instance.pool} \
                --wallet ${instance.wallet} \
                --gpu-id 0 \
                --tls true
            ''}/bin/lpminer-${instance.name}";
            Restart = "always";
            RestartSec = "10";
          };
        };
      }) config.services.lpminer.instances
    );
  };
}
