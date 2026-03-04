# Gamescope HDR configuration - separate module for hosts with HDR displays
# Import this on zephyr only (not nexus - no HDR display)
{
  config,
  lib,
  ...
}:
with lib;
let
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
in
{
  options.services.gaming.hdr.enable =
    mkEnableOption "Enable HDR support in Gamescope (zephyr needs this, nexus doesn't)";

  config = mkIf cfg.hdr.enable {
    # Override gamescope args to add HDR support and SDL backend
    programs.gamescope.args = hdrArgs ++ baseArgs;
  };
}
