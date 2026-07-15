{ lib, appimageTools, fetchurl }:

# Freebuff desktop — Codebuff's free coding-agent GUI (Electron AppImage).
#
# Root cause of the original failure (2026-07-15):
#   The AppImage's AppRun uses `#!/bin/bash` as its shebang, which does NOT
#   exist on NixOS (only /bin/sh and /usr/bin/env). The kernel fails with
#   "bad interpreter: No such file or directory" before the binary even runs.
#   Once past bash, the extracted Electron binary also needs system libs
#   (libglib-2.0.so.0, libnss3.so, ...) that are absent from NixOS's non-FHS
#   layout -> "error while loading shared libraries".
#
# Fix: appimageTools.wrapType2 builds the AppImage into a proper FHS
# environment (provides /bin/bash + system libs) so it launches natively.
# Verified locally: no /bin/bash or missing-lib errors; Electron starts.
#
# The AppImage is cached locally at ~/.local/share/freebuff/Freebuff-x86_64.AppImage
# (downloaded by the legacy wrapper / `freebuff-desktop --update`). We import that
# file as a fixed source so the build is reproducible from the existing cache.
# To bump versions, replace the cached file and update `version` + `hash` below.
let
  version = "0.0.18";

  # Local cache path — import as a fixed source (reproducible, no network at build).
  localSrc = /home/j_kro/.local/share/freebuff/Freebuff-x86_64.AppImage;

  # Network fallback (used if you prefer not to keep a local cache).
  # fetchSrc = fetchurl {
  #   url = "https://github.com/CodebuffAI/codebuff-community/releases/download/v${version}/Freebuff-${version}-linux-x86_64.AppImage";
  #   sha256 = lib.fakeSha256; # replace after first build prints the real hash
  # };

  pname = "freebuff-desktop";
in
appimageTools.wrapType2 {
  inherit pname version;
  src = localSrc;
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
