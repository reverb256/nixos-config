# Freebuff Desktop — auto-updating AppImage launcher (via freebuff-flake).
#
# Replaces the old packages/freebuff-desktop.nix (wrapType2, static version).
# Uses freebuff-flake's wrapper which handles:
#   - Automatic AppImage download + update (24h throttle)
#   - Extraction (appimage-extract → 7z fallback)
#   - NVIDIA GPU library injection (LD_PRELOAD + __EGL_VENDOR_LIBRARY_FILENAMES)
#   - Wayland/Ozone display configuration
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib; let
  cfg = config.services.freebuff-desktop;
  freebuff-wrapper = inputs.freebuff-flake.packages.${pkgs.stdenv.hostPlatform.system}.freebuff-desktop-wrapper;
in {
  options.services.freebuff-desktop = {
    enable = mkEnableOption "Freebuff Desktop — auto-updating coding-agent GUI";
    package = mkOption {
      type = types.package;
      default = freebuff-wrapper;
      description = "The freebuff-desktop auto-updating wrapper package.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
