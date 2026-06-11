{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.amdgpu.powerLimits;
  inherit (lib) mkEnableOption mkOption mkIf types;
in {
  options.hardware.amdgpu.powerLimits = {
    enable = mkEnableOption "AMD GPU power limits (per-GPU, via rocm-smi)";

    gpus = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          index = mkOption {
            type = types.ints.unsigned;
            description = "GPU index as shown by rocm-smi";
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
          "rx5700xt-0" = { index = 0; limit = 120; };
          "rx5700xt-1" = { index = 1; limit = 120; };
        }
      '';
      description = "Per-GPU power limits keyed by GPU name";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.amdgpu-power-limits = mkIf (cfg.gpus != {}) {
      description = "Set AMD GPU power limits via rocm-smi";
      wantedBy = ["multi-user.target"];
      after = ["systemd-modules-load.service"];
      path = [config.hardware.graphics.package] ++ (with pkgs.rocmPackages; [rocm-smi clr]);
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
        ExecStart = pkgs.writeShellScript "set-amd-gpu-power" (
          lib.concatStringsSep "\n"
          (lib.mapAttrsToList
            (name: gpu: "rocm-smi -d ${toString gpu.index} --setpoweroverdrive ${toString gpu.limit}")
            cfg.gpus)
        );
      };
    };
  };
}
