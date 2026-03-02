# Gamescope HDR configuration - separate module for hosts with HDR displays
# Import this on zephyr only (not nexus - no HDR display)
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.gaming;
in {
  options.services.gaming.hdr.enable = mkEnableOption "Enable HDR support in Gamescope (zephyr needs this, nexus doesn't)";

  config = mkIf (cfg.enable && cfg.hdr.enable) {
    # Override gamescope env to add HDR settings
    programs.gamescope = mkIf cfg.enable {
      env = mkMerge [
        {
          ENABLE_GAMESCOPE_WSI = "1";
          DXVK_HDR = "1";
        }
      ];
      args = mkIf cfg.enable [
        "--backend sdl"
        "--immediate-flips"
        "--rt"
        "--steam"
        "--xwayland-count 2"
        "--force-composition"
        "--expose-wayland"
        "--hdr-enabled"
        "--hdr-itm-enabled"
      ];
    };
  };
}
