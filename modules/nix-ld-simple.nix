{ pkgs, ... }:

{
  # ============================================================================
  # DYNAMIC LINKER SUPPORT - nix-ld for mining binaries and browsers
  # ============================================================================
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      "libstdc++"
      zlib
      libxcb
      libX11
      libXext
      libXrandr
      libXcomposite
      libXdamage
      libXi
      gtk3
      pango
      cairo
      gdk-pixbuf
      libglib
      gio
      dbus
      alsa-lib
      freetype
      fontconfig
    ];
  };
}