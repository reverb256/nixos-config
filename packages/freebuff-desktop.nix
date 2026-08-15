{
  lib,
  pkgs,
  appimageTools,
  fetchurl,
  # 2026-08-15: absolute path to the NVIDIA Vulkan ICD to export. The host
  # config computes it from config.hardware.nvidia.package (the system
  # driver) so it matches the running driver; a nix store path is reachable
  # inside the AppImage bwrap sandbox via /nix. Default keeps the standard
  # /run/opengl-driver discovery for standalone builds.
  nvidiaIcdPath ? "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json",
}:
# Freebuff desktop — Codebuff's free coding-agent GUI (Electron AppImage).
#
# FIX (2026-07-15): appimageTools.wrapType2 fixes two NixOS failures:
#   1. AppRun shebang '#!/bin/bash' (doesn't exist on NixOS) -> 'bad interpreter'
#   2. Extracted Electron binary needs libglib-2.0.so.0, libnss3.so absent from
#      non-FHS layout -> 'error while loading shared libraries'
#
# FIX (2026-07-28): Added GPU/rendering libraries and env vars for NixOS Wayland.
#   - GPU init was failing: 'egl: failed to create dri2 screen'
#   - Added mesa, vulkan-loader, nvidia_x11 to FHS sandbox
#   - Added --no-sandbox --disable-gpu-sandbox Electron flags
#   - Added LD_LIBRARY_PATH, VK_ICD_FILENAMES, NIXOS_OZONE_WL env vars
#
# wrapType2 provides a proper FHS environment (bash + system libs) at runtime.
#
# The download URL (freebuff.com/api/desktop/download/linux) redirects to the
# latest AppImage. The sha256 pins the current version. To upgrade, re-fetch
# and update the hash.
let
  pname = "freebuff-desktop";
  version = "0.0.42"; # approximate; actual version is determined by the API
  src = fetchurl {
    url = "https://freebuff.com/api/desktop/download/linux";
    # Hash of the AppImage served by the API as of 2026-08-13 (v0.0.42),
    # verified by a real build. (The freebuff-flake flake input that used to
    # carry this package was removed 2026-08-13 — this repo is the single
    # source.) The API always redirects to the latest build, so re-verify on
    # every upgrade:
    #   nix build .#nixosConfigurations.zephyr.pkgs.freebuff-desktop
    #   copy the expected hash from the failed build output.
    sha256 = "sha256-1TB2NUe9ECI20cUtAjK2CJaN5YnbCSr7HW/MkON3Mdo=";
  };
  # Extract the icon from the AppImage first
  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
  };
in
  appimageTools.wrapType2 {
    inherit pname version src;
    extraPkgs = pkgs:
      with pkgs; [
        # Electron core dependencies
        bash
        glib
        nss
        nspr
        libGL
        fontconfig
        freetype
        alsa-lib
        cups
        dbus
        expat
        xorg.libX11
        xorg.libXcomposite
        xorg.libXdamage
        xorg.libXext
        xorg.libXfixes
        xorg.libXrandr
        xorg.libxcb
        xorg.libxkbfile
        xorg.libXScrnSaver
        xorg.libXi
        xorg.libXtst
        libxshmfence
        libxkbcommon
        libgbm
        pango.out
        cairo
        gtk3
        systemd
        udev
        stdenv.cc.cc.lib
        # GPU / rendering libraries (NixOS Wayland fix)
        mesa
        libdrm
        vulkan-loader
        # NVIDIA driver passthrough is handled via LD_LIBRARY_PATH=/run/opengl-driver/lib
        # in the profile block, so nvidia_x11 is NOT included here to avoid
        # unfree license issues with home-manager callPackage.
      ];

    # Environment variables for GPU rendering on NixOS Wayland.
    # profile runs inside the FHS sandbox before the app.
    profile = ''
      # NVIDIA driver libraries
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:''${LD_LIBRARY_PATH:-}"
      # Vulkan ICD: the .x86_64-suffixed filename does NOT exist on this
      # host (real file is nvidia_icd.json, no arch suffix). Point at the
      # nix store path which the FHS sandbox can reach via /nix, instead of
      # /run/opengl-driver which the AppImage bwrap may shadow. 2026-08-15.
      export VK_ICD_FILENAMES="${nvidiaIcdPath}"
      # Wayland / Ozone
      export NIXOS_OZONE_WL=1
      export ELECTRON_OZONE_PLATFORM_HINT=wayland
    '';

    extraInstallCommands = ''
      # Install the icon from the extracted AppImage
      mkdir -p $out/share/icons/hicolor/512x512/apps
      cp ${appimageContents}/@codebufffreebuff-desktop.png \
         $out/share/icons/hicolor/512x512/apps/freebuff.png 2>/dev/null || \
      cp ${appimageContents}/*freebuff*.png \
         $out/share/icons/hicolor/512x512/apps/freebuff.png 2>/dev/null || \
      cp ${appimageContents}/*.png \
         $out/share/icons/hicolor/512x512/apps/freebuff.png 2>/dev/null || true

      # Also install to scalable location for compatibility
      mkdir -p $out/share/icons/hicolor/scalable/apps
      cp $out/share/icons/hicolor/512x512/apps/freebuff.png \
         $out/share/icons/hicolor/scalable/apps/freebuff.png 2>/dev/null || true
    '';

    meta = with lib; {
      description = "Freebuff Desktop — GitHub-native coding-agent orchestrator";
      homepage = "https://freebuff.com";
      platforms = ["x86_64-linux"];
      mainProgram = "freebuff-desktop";
    };
  }
