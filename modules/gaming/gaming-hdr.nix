{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.gaming;
  baseArgs = [
    "--immediate-flips"
    "--rt"
    "--steam"
    "--xwayland-count 2"
    "--force-composition"
    "--expose-wayland"
  ];
  hdrArgs = [
    "--backend sdl"
    "--hdr-enabled"
    "--hdr-itm-enabled"
  ];
in {
  options.services.gaming.hdr.enable =
    mkEnableOption "Enable HDR support in Gamescope (zephyr needs this, nexus doesn't)";

  config = mkIf cfg.hdr.enable {
    programs.gamescope.args = hdrArgs ++ baseArgs;
  };
}
