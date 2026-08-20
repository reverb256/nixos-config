# Gaming / VR / Steam module bundle — DESKTOP HOSTS ONLY.
#
# Loaded via contracts/host-inventory.nix `extraModules` for zephyr + nexus
# (the gaming/Vulkan hosts). Headless hosts (sentry, forge) do NOT include
# this, so they never pull the Steam/VR/ScopeBuddy/DualSense closure.
#
# This mirrors the existing desktop-modules.nix pattern (zephyr-only AAGL +
# Niri). Keeping gaming out of modules/default.nix (which is in
# commonModules for every host) is what prevented sentry from being a
# headless k3s control-plane + inference box without a 2GB Steam stack.
#
# Ref: j_kro directive "get the steam and vr and gaming stuff off sentry —
# make profiles" (2026-08-20).
{ inputs, pkgs, ... }: {
  imports = [
    # ScopeBuddy gamescope wrapper (enable=true unconditionally upstream —
    # only meaningful on a desktop host with a display). THE leak we moved off
    # headless hosts.
    ./gaming/scopebuddy.nix
    # Fleet-wide Sony DualSense input support (enable=mkDefault true — defaults
    # on for all hosts; headless sentry/forge don't need gamepad plumbing).
    ./gaming/dualsense.nix
    # Desktop media theming (Spotify) — desktop only.
    ./desktop/spotify-spotx.nix
    # Multimedia/GStreamer — desktop audio/video stack.
    ./multimedia/gstreamer.nix
  ];

  # Gaming system packages — desktop hosts only. vulkan-loader/vulkan-tools are
  # intentionally KEPT in modules/system/system-packages.nix (headless sentry
  # needs RADV Vulkan for Bonsai/llama-swap inference).
  environment.systemPackages = with pkgs; [
    steam-run
    pkgsi686Linux.glibc
    xrizer
    opencomposite
    vulkan-validation-layers
    vulkan-headers
    dxvk
    wine
    winetricks
  ];
}
