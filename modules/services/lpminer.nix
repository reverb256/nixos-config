{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.lpminer = {
    enable = lib.mkEnableOption "LPMiner GPU mining";

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
            default = "stratum+ssl://prl-us.kryptex.network:8048,stratum+ssl://prl.kryptex.network:8048";
            description = "Mining pool URL";
          };
        };
      });
      default = [];
      description = "List of LPMiner instances";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User to run miner as";
    };
  };

  config = lib.mkIf config.services.lpminer.enable {
    systemd.services = lib.listToAttrs (
      builtins.map (instance: {
        name = "lpminer-${instance.name}";
        value = {
          description = "LPMiner - ${instance.name}";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target"];

          serviceConfig = {
            Type = "simple";
            User = config.services.lpminer.user;
            Environment = ["CUDA_VISIBLE_DEVICES=${toString instance.gpuId}"];
            ExecStart = pkgs.writeShellScript "lpminer-${instance.name}" ''
              cd /home/j_kro/lpminer-${instance.name}
              exec ./lpminer --pearl-mine --pool "${instance.pool}" --wallet "${instance.wallet}" --device 0
            '';
            Restart = "always";
            RestartSec = "5";
          };
        };
      })
      config.services.lpminer.instances
    );
  };
}
