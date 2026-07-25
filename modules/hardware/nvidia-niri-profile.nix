{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.nvidia-niri-profile;
in {
  options.hardware.nvidia-niri-profile = {
    enable = lib.mkEnableOption "NVIDIA per-process app profile for niri (VRAM leak fix)";
  };

  config = lib.mkIf cfg.enable {
    # The NVIDIA driver has a heap-reuse quirk where it doesn't release VRAM
    # back to the pool. This profile forces GLVidHeapReuseRatio=0 for niri,
    # keeping VRAM usage at ~100 MiB instead of ballooning to 1+ GiB.
    # See: https://github.com/niri-wm/niri/wiki/Nvidia
    environment.etc."nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-niri.json" = {
      text = builtins.toJSON {
        rules = [
          {
            pattern = {
              feature = "procname";
              matches = "niri";
            };
            profile = "Limit Free Buffer Pool On Wayland Compositors";
          }
        ];
        profiles = [
          {
            name = "Limit Free Buffer Pool On Wayland Compositors";
            settings = [
              {
                key = "GLVidHeapReuseRatio";
                value = 0;
              }
            ];
          }
        ];
      };
    };
  };
}
