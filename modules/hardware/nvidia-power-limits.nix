{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.nvidia.powerLimits;
  inherit (lib) mkEnableOption mkOption mkIf types;

  # Shell-sourceable config: POWER_<profile>_<gpu_pattern>=<watts>
  profilesConfContent = lib.concatStringsSep "\n" (
    lib.flatten (
      lib.mapAttrsToList (
        profileName: gpuLimits:
          lib.mapAttrsToList (
            gpuPattern: watts: "POWER_${profileName}_${gpuPattern}=${toString watts}"
          )
          gpuLimits
      )
      cfg.profiles
    )
  );

  bootLimitsContent = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      gpuName: gpu: "POWER_boot_${gpuName}=${toString gpu.limit}"
    )
    cfg.gpus
  );
in {
  options.hardware.nvidia.powerLimits = {
    enable = mkEnableOption "NVIDIA GPU power limits (per-GPU, per-profile, via nvidia-smi)";

    gpus = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          index = mkOption {
            type = types.ints.unsigned;
            description = "GPU index as shown by nvidia-smi";
          };
          limit = mkOption {
            type = types.ints.unsigned;
            description = "Boot-time power limit in watts (floor before any profile activates)";
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
      description = "Per-GPU boot-time power limits keyed by GPU name pattern";
    };

    profiles = mkOption {
      type = types.attrsOf (types.attrsOf types.ints.unsigned);
      default = {};
      example = lib.literalExpression ''
        {
          gaming = { "3060" = 200; "3090" = 350; };
          ai = { "3060" = 110; "3090" = 300; };
          mining = { "3060" = 130; "3090" = 250; };
          idle = { "3060" = 200; "3090" = 350; };
        }
      '';
      description = "Per-profile power limits. Keys are profile names, values are attrsets of GPU pattern -> watts. GPU patterns are substring-matched against nvidia-smi output.";
    };
  };

  config = mkIf cfg.enable {
    # Generate the config file for the profile manager to source
    environment.etc."nvidia-power-profiles.conf".text =
      profilesConfContent + "\n" + bootLimitsContent + "\n";

    # Boot-time service: apply base power limits before profile manager starts
    systemd.services.nvidia-power-limits = mkIf (cfg.gpus != {}) {
      description = "Set NVIDIA GPU boot-time power limits";
      wantedBy = ["multi-user.target"];
      after = ["nvidia-persistenced.service"];
      before = ["gpu-profile-manager.service"];
      path = [config.hardware.nvidia.package.bin];
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
        ExecStart = pkgs.writeShellScript "set-gpu-power-boot" (
          lib.concatStringsSep "\n"
          (lib.mapAttrsToList
            (name: gpu: "nvidia-smi -i ${toString gpu.index} -pl ${toString gpu.limit}")
            cfg.gpus)
        );
      };
    };
  };
}
