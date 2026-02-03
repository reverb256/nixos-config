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
      
      # === X11 LIBRARIES ===
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXdamage
      xorg.libxcb
      xorg.libxshmfence
      xorg.libXfixes
      xorg.libXxf86vm
      xorg.libXcursor
      xorg.libXft
      xorg.libXrender
      xorg.libXtst
      xorg.libXi
      xorg.libXcomposite
      xorg.libXinerama
      xorg.libXScrnSaver
      
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
      pipewire.lib  # Add pipewire client library for Qt6 multimedia (libpipewire-0.3.so)
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
      libxcb
      libX11
      libXext
      libXrandr
      libXcomposite
      libXdamage
      libXi
      nspr
      nss
      xorg.libXcursor
      xorg.libXfixes
      xorg.libXft
      xorg.libXrender
      xorg.libXtst
      
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
