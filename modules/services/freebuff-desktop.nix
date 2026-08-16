# Freebuff Desktop — auto-updating coding-agent GUI for NixOS/NVIDIA.
#
# The freebuff-flake provides freebuff-desktop-latest which manages the
# AppImage download/update in ~/.local/opt/freebuff-desktop. This NixOS
# module wraps it with the required NVIDIA GLVND/EGL env vars that the
# upstream wrapper omits (causing EGL initialization failures on NVIDIA).
#
# Also installs the icon (extracted from the AppImage) and the .desktop
# entry declaratively -- replacing the hand-placed files.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.freebuff-desktop;

  nvidiaDriver = config.hardware.nvidia.package;
  nvidiaEglVendor = "${nvidiaDriver}/share/glvnd/egl_vendor.d/10_nvidia.json";
  nvidiaIcdPath = "${nvidiaDriver}/share/vulkan/icd.d/nvidia_icd.json";
  libglvndLib = "${pkgs.libglvnd}/lib";

  # Icon extracted from the AppImage (512x512 RGBA PNG).
  # Installed into the hicolor theme so Icon=freebuff resolves.
  freebuff-icon = pkgs.runCommand "freebuff-icon" {} ''
    mkdir -p "$out/share/icons/hicolor/512x512/apps"
    cp ${./assets/freebuff-icon.png} "$out/share/icons/hicolor/512x512/apps/freebuff.png"
  '';

  # Wrapper script: adds NVIDIA GLVND/EGL env vars the upstream launcher
  # omits. The upstream freebuff-desktop-latest only sets VK_ICD_FILENAMES
  # and Ozone hints -- it does NOT set __EGL_VENDOR_LIBRARY_FILENAMES,
  # LD_LIBRARY_PATH (libglvnd), or LIBGL_DRIVERS_PATH. Without these,
  # Electron picks Mesa instead of NVIDIA -> black screen / GL errors.
  wrappedLatest = pkgs.writeShellScriptBin "freebuff-desktop-latest" ''
    set -u
    STATE="''${HOME}/.local/opt/freebuff-desktop"
    LOCAL="$STATE/current"

    if [ -x "$LOCAL/bin/freebuff-desktop" ]; then
      # NVIDIA GLVND vendor selection (libEGL.so.1 from libglvnd)
      export __EGL_VENDOR_LIBRARY_FILENAMES="${nvidiaEglVendor}"
      export VK_ICD_FILENAMES="${nvidiaIcdPath}"
      export LIBGL_DRIVERS_PATH="${nvidiaDriver}/lib/dri:/run/current-system/sw/lib/dri"
      export LD_LIBRARY_PATH="${libglvndLib}:${nvidiaDriver}/lib:/run/current-system/sw/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

      # Wayland/Ozone
      export NIXOS_OZONE_WL=1
      export ELECTRON_OZONE_PLATFORM_HINT=wayland
      export MOZ_ENABLE_WAYLAND=1
      export GDK_BACKEND=wayland

      exec "$LOCAL/bin/freebuff-desktop" --no-sandbox --disable-gpu-sandbox "$@"
    fi
    exec freebuff-desktop --no-sandbox --disable-gpu-sandbox "$@"
  '';

  # .desktop entry -- declarative, replaces hand-placed
  # ~/.local/share/applications/freebuff-desktop.desktop.
  desktopEntry = pkgs.makeDesktopItem {
    name = "freebuff-desktop";
    desktopName = "Freebuff";
    genericName = "Coding Agent Orchestrator";
    comment = "Freebuff Desktop — GitHub-native coding-agent orchestrator";
    exec = "freebuff-desktop-latest %U";
    icon = "freebuff";
    categories = ["Development" "Utility"];
    startupNotify = true;
    startupWMClass = "Freebuff";
    terminal = false;
    type = "Application";
  };
in {
  options.services.freebuff-desktop = {
    enable = mkEnableOption "Freebuff Desktop — auto-updating coding-agent GUI";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      wrappedLatest
      freebuff-icon
      desktopEntry
    ];
  };
}
