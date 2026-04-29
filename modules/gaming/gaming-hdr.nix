{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.gaming;
in {
  options.services.gaming.hdr.enable =
    mkEnableOption "Enable HDR support in Gamescope (zephyr needs this, nexus doesn't)";

  config = mkIf cfg.hdr.enable {
    # Prepend HDR args — they merge with base args from gaming.nix
    programs.gamescope.args = lib.mkBefore [
      "--backend sdl"
      "--hdr-enabled"
      "--hdr-itm-enabled"
    ];
  };
}
