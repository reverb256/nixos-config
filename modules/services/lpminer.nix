{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.lpminer;
  inherit (lib) mkEnableOption mkOption types mkIf mkBefore;
in {
  options.services.lpminer = {
    enable = mkEnableOption "LPMiner GPU mining";

    instances = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Service name suffix";
          };
          gpuId = mkOption {
            type = types.int;
            description = "GPU ID to use";
          };
          wallet = mkOption {
            type = types.str;
            description = "Wallet address";
          };
          pool = mkOption {
            type = types.str;
            default = "stratum+ssl://prl-us.kryptex.network:8048,stratum+ssl://prl.kryptex.network:8048";
            description = "Mining pool URL(s), comma-separated";
          };
          powerLimit = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "GPU power limit in watts (null = no change)";
          };
        };
      });
      default = [];
      description = "List of LPMiner instances";
    };

    user = mkOption {
      type = types.str;
      default = "j_kro";
      description = "User to run miner as";
    };
  };

  config = mkIf cfg.enable {
    systemd.services = lib.listToAttrs (
      builtins.map (instance: let
        powerLimitArgs = if instance.powerLimit != null then
          "+/run/current-system/sw/bin/nvidia-smi -i ${toString instance.gpuId} -pl ${toString instance.powerLimit}"
        else "";
      in {
        name = "lpminer-${instance.name}";
        value = {
          description = "LPMiner - ${instance.name}";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            ExecStartPre = mkIf (instance.powerLimit != null) (
              mkBefore powerLimitArgs
            );
            ExecStart = pkgs.writeShellScript "lpminer-${instance.name}" ''
              export CUDA_DEVICE_ORDER=PCI_BUS_ID
              export CUDA_VISIBLE_DEVICES=${toString instance.gpuId}
              export LD_LIBRARY_PATH=/run/opengl-driver/lib
              exec ${pkgs.lpminer-pearl}/bin/lpminer --pearl-mine \
                --pool "${instance.pool}" \
                --wallet "${instance.wallet}" \
                --device 0
            '';
            Restart = "always";
            RestartSec = "5";
          };
        };
      }) cfg.instances
    );
  };
}
