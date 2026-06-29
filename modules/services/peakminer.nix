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
          gpuId = mkOption {
            type = types.int;
            default = 0;
            description = "NVIDIA GPU device index for nvidia-smi power limit";
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
            default = ["--legacy-auth"];  # Kryptex needs standard Stratum V1 array auth format
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
          then "+/run/current-system/sw/bin/nvidia-smi -i ${toString instance.gpuId} -pl ${toString instance.powerLimit}"
          else "";
        powerArg =
          if instance.powerLimit != null
          then []  # Power limit set via nvidia-smi ExecStartPre, not --gpu-power (NVML unreliable on NixOS)
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
            # ExecStartPost re-applies the power limit AFTER peakminer starts,
            # because peakminer's NVML OC silently fails on NixOS and leaves
            # the GPU at its default power envelope. nvidia-smi -pl works reliably.
            ExecStartPost = lib.mkIf (instance.powerLimit != null) (
              "+/run/current-system/sw/bin/nvidia-smi -i ${toString instance.gpuId} -pl ${toString instance.powerLimit}"
            );
            ExecStart = pkgs.writeShellScript "peakminer-${instance.name}" ''
              export CUDA_DEVICE_ORDER=PCI_BUS_ID
              # PeakMiner needs NVML + CUDA runtime libraries from the driver
              export LD_LIBRARY_PATH=/run/opengl-driver/lib:''${LD_LIBRARY_PATH:-}
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
