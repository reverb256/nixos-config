{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.peakminer;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.peakminer = {
    enable = mkEnableOption "PeakMiner GPU mining (Pearl/PRL)";

    instances = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Service name suffix (e.g. forge-4060-0)";
          };
          wallet = mkOption {
            type = types.str;
            description = "Mining wallet with worker suffix";
          };
          pools = mkOption {
            type = types.listOf types.str;
            default = ["stratum+tcp://prl-us.kryptex.network:7048"];
            description = "List of pool URLs (failover order)";
          };
          devices = mkOption {
            type = types.str;
            default = "all";
            description = "GPU device indices: all or comma-separated (e.g. 0,1)";
          };
          powerLimit = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "GPU power limit in watts (null = no change)";
          };
          apiPort = mkOption {
            type = types.port;
            default = 4068;
            description = "HTTP stats API port";
          };
          tempStop = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "Pause GPU at this temperature (°C)";
          };
          extraArgs = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Extra peakminer CLI arguments";
          };
        };
      });
      default = [];
      description = "List of PeakMiner instances";
    };

    user = mkOption {
      type = types.str;
      default = "root";
      description = "User to run miner as (root needed for OC/power control)";
    };
  };

  config = mkIf cfg.enable {
    systemd.services = lib.listToAttrs (
      builtins.map (instance: let
        poolArgs = builtins.map (p: "--url ${p}") instance.pools;
        powerLimitArgs =
          if instance.powerLimit != null
          then "+/run/current-system/sw/bin/nvidia-smi -i 0 -pl ${toString instance.powerLimit}"
          else "";
        powerArg =
          if instance.powerLimit != null
          then ["--gpu-power ${toString instance.powerLimit}"]
          else [];
        tempArg =
          if instance.tempStop != null
          then ["--gpu-temp-stop ${toString instance.tempStop}"]
          else [];
      in {
        name = "peakminer-${instance.name}";
        value = {
          description = "PeakMiner - ${instance.name}";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target"];

          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            ExecStartPre = lib.mkIf (instance.powerLimit != null) (
              lib.mkBefore powerLimitArgs
            );
            ExecStart = pkgs.writeShellScript "peakminer-${instance.name}" ''
              export CUDA_DEVICE_ORDER=PCI_BUS_ID
              exec ${pkgs.peakminer}/bin/peakminer \
                --coin pearl \
                ${lib.concatStringsSep " " poolArgs} \
                --user ${instance.wallet} \
                --devices ${instance.devices} \
                --api-port ${toString instance.apiPort} \
                ${lib.concatStringsSep " " powerArg} \
                ${lib.concatStringsSep " " tempArg} \
                ${lib.concatStringsSep " " instance.extraArgs}
            '';
            Restart = "always";
            RestartSec = 10;
          };
        };
      }) cfg.instances
    );
  };
}
