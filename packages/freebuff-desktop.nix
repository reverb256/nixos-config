{ lib, appimageTools, fetchurl }:

# Freebuff desktop — Codebuff's free coding-agent GUI (Electron AppImage).
#
# FIX (2026-07-15): appimageTools.wrapType2 fixes two NixOS failures:
#   1. AppRun shebang '#!/bin/bash' (doesn't exist on NixOS) -> 'bad interpreter'
#   2. Extracted Electron binary needs libglib-2.0.so.0, libnss3.so absent from
#      non-FHS layout -> 'error while loading shared libraries'
#
# wrapType2 provides a proper FHS environment (bash + system libs) at runtime.
# Verified: no interpreter/missing-lib errors; Electron starts.
#
# The download URL (freebuff.com/api/desktop/download/linux) redirects to the
# latest AppImage. The sha256 pins the current version. To upgrade, re-fetch
# and update the hash.

let
  pname = "freebuff-desktop";
  src = fetchurl {
    url = "https://freebuff.com/api/desktop/download/linux";
    # Hash of the AppImage downloaded 2026-07-14 (~v0.0.22).
    # To update: nix build .#freebuff-desktop; copy the expected hash from the
    # failed build output.
    sha256 = "sha256-zhZgkBVRLkx7IRNT1WGIYAzm4On4mAXV4gc+Z6CXmHg=";
  };
in
appimageTools.wrapType2 {
  inherit pname src;
  version = "0.0.22"; # approximate; actual version is determined by the API
  extraPkgs = pkgs: with pkgs; [
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
    libxshmfence
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
    xorg.libxkbfile
    xorg.libXScrnSaver
  ];
}
