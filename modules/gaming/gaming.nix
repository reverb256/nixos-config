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
  # set-evdev-deadzone derivation removed 2026-07-29 (Phase 3 cleanup).
  # It was only used in a commented-out udev rule in the old monolithic
  # gaming.nix. If re-enabling kernel-level deadzone, restore the
  # derivation here and uncomment the RUN+= rule in gaming-base.nix.
in {
  options.services.gaming = {
    enable = mkEnableOption "Gaming support (Steam, GameMode, Gamescope)";
    gpuFilter = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        GPU name to pin DXVK/DXVK-NVAPI to and target with the GameMode
        overclock hook (DXVK_FILTER_DEVICE_NAME). Set this to the
        display-attached GPU name on multi-GPU hosts — e.g.
        "NVIDIA GeForce RTX 3090" on zephyr — and leave it null on
        single-GPU hosts (nexus) for normal loader discovery.
      '';
    };
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
    ./gaming-vr-unlock.nix
  ];
}
