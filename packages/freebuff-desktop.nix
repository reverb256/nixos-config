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

let
  version = "0.0.18";
  # Version pinned to the GitHub release URL. To bump, update version + sha256.
  # The sha256 is the nix hash of the downloaded AppImage.
  src = fetchurl {
    url = "https://github.com/CodebuffAI/codebuff-community/releases/download/v${version}/Freebuff-${version}-linux-x86_64.AppImage";
    sha256 = "sha256-MP929iWwqeiNv3V+ksl9/HvpFefFcv3b0mZSK2AUUEs=";
  };
  pname = "freebuff-desktop";
in
appimageTools.wrapType2 {
  inherit pname version src;
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
