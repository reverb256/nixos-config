{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.nvidia.powerLimits;
  inherit (lib) mkEnableOption mkOption mkIf types;
in {
  options.hardware.nvidia.powerLimits = {
    enable = mkEnableOption "NVIDIA GPU power limits (per-GPU, via nvidia-smi)";

    gpus = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          index = mkOption {
            type = types.ints.unsigned;
            description = "GPU index as shown by nvidia-smi";
          };
          limit = mkOption {
            type = types.ints.unsigned;
            description = "Power limit in watts";
          };
        };
      });
      default = {};
      example = lib.literalExpression ''
        {
          "3060ti" = { index = 0; limit = 100; };
          "3090" = { index = 1; limit = 250; };
        }
      '';
      description = "Per-GPU power limits keyed by name";
    };
  };

  config = mkIf (cfg.enable && cfg.gpus != {}) {
    systemd.services.nvidia-power-limits = {
      description = "Set NVIDIA GPU power limits";
      wantedBy = ["multi-user.target"];
      after = ["nvidia-persistenced.service"];
      path = [config.hardware.nvidia.package.bin];
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
        ExecStart = pkgs.writeShellScript "set-gpu-power" (
          lib.concatStringsSep "\n"
          (lib.mapAttrsToList
            (name: gpu: "nvidia-smi -i ${toString gpu.index} -pl ${toString gpu.limit}")
            cfg.gpus)
        );
      };
    };
  };
}
