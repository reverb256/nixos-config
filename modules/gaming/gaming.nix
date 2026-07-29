# Gaming Module — Steam, GameMode, Gamescope, MangoHud, VR (WiVRn).
# Phase 3 de-monolith (2026-07-29): base config + VR config extracted.
#   ./gaming-base.nix — programs (gamemode/steam/gamescope/nix-ld),
#                       services (pipewire/udev), environment, etc.
#   ./gaming-vr.nix   — WiVRn, Avahi, SteamVR/OpenXR, gpu-profile
#
# VR is gated by services.gaming.vr.enable option.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.gaming;
  vrCfg = cfg.vr;
  # Kernel-level deadzone tool for controllers
  set-evdev-deadzone = pkgs.stdenv.mkDerivation {
    pname = "set-evdev-deadzone";
    version = "1.0.0";
    src = ./files;
    buildPhase = ''
      gcc -O2 -Wall -o set-evdev-deadzone set-evdev-deadzone.c
    '';
    installPhase = ''
      mkdir -p $out/bin
      cp set-evdev-deadzone $out/bin/
    '';
    nativeBuildInputs = [pkgs.gcc];
  };
in {
  options.services.gaming = {
    enable = mkEnableOption "Gaming support (Steam, GameMode, Gamescope)";
    vr = {
      enable = mkEnableOption "VR support (WiVRn, SteamVR, OpenXR)";
      encoder = mkOption {
        type = types.enum [
          "nvenc"
          "x264"
          "av1"
        ];
        default = "nvenc";
        description = "Video encoder for WiVRn streaming";
      };
      refreshRate = mkOption {
        type = types.int;
        default = 90;
        description = "Target refresh rate for VR headset";
      };
      resolution = mkOption {
        type = types.str;
        default = "2160x2160";
        description = "Per-eye resolution for VR streaming";
      };
    };
  };

  imports = [
    ./gaming-base.nix
    ./gaming-vr.nix
  ];
}
