{pkgs, ...}: {
  # ============================================================================
  # DYNAMIC LINKER SUPPORT - nix-ld for Proton, mining binaries and browsers
  # ============================================================================
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # === BASE LIBRARIES ===
      zlib
      zstd
      stdenv.cc.cc.lib
      curl
      openssl
      attr
      libssh
      bzip2
      libxml2
      acl
      libsodium
      util-linux
      xz
      systemd

      # === 32-BIT COMPATIBILITY ===
      # Essential for Proton/Steam games
      pkgsi686Linux.zlib
      pkgsi686Linux.stdenv.cc.cc.lib

      # === GRAPHICS & GPU ===
      libGL
      libglvnd
      vulkan-loader
      libdrm
      libva
      mesa
      pipewire
      libxkbcommon
      wayland
      wayland-protocols

      # === X11 LIBRARIES (new package names, not deprecated xorg.*) ===
      libX11
      libXext
      libxrandr
      libXdamage
      libxcb
      libxshmfence
      libXfixes
      libXxf86vm
      libxcursor
      libXft
      libXrender
      libXtst
      libxi
      libXcomposite
      libxinerama
      libxscrnsaver

      # === GTK & GUI ===
      glib
      gtk2
      gtk3
      gtk4
      pango
      cairo
      atk
      gdk-pixbuf
      fontconfig
      freetype

      # === AUDIO ===
      alsa-lib
      alsa-plugins
      pulseaudio
      libpulseaudio
      pipewire.dev # Add pipewire client library for Qt6 multimedia (libpipewire-0.3.so)
      libvorbis
      flac
      libogg

      # === NETWORKING & DBUS ===
      expat
      dbus
      dbus-glib
      libusb1

      # === MEDIA ===
      ffmpeg
      SDL2
      SDL2_image
      SDL2_mixer
      SDL2_ttf
      libpng
      libjpeg
      libtiff
      libwebp

      # === BROWSER LIBRARIES ===
      nspr
      nss

      # === ADDITIONAL GAME LIBRARIES ===
      libgcrypt
      libgpg-error
      libxslt
      libsecret
      gmp
      nettle
      gnutls
      libidn2
      libpsl
      nghttp2
      rtmpdump

      # === CUDA ===
      cudaPackages.cuda_cudart
      cudaPackages.cudnn
      cudaPackages.libcublas
      cudaPackages.libcufft

      # === NVIDIA SPECIFIC ===
      nvidia-vaapi-driver
    ];
  };
}
