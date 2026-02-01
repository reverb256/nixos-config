{pkgs, ...}: {
  # ============================================================================
  # DYNAMIC LINKER SUPPORT - nix-ld for mining binaries and browsers
  # ============================================================================
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # Defaults (already included in recent nixpkgs)
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

      # Common for GPU/mining/proprietary (add more as needed)
      libGL
      vulkan-loader
      libdrm
      libva
      pipewire
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXdamage
      xorg.libxcb
      xorg.libxshmfence
      xorg.libXfixes
      xorg.libXxf86vm
      glib
      gtk3
      pango
      cairo
      atk
      gdk-pixbuf
      fontconfig
      freetype
      alsa-lib
      expat
      dbus
      libusb1
      ffmpeg
      SDL2

      # Browser-specific libraries for Chrome DevTools & Playwright MCP
      # libstdc++ is already included as stdenv.cc.cc.lib above
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

      # CUDA libraries for LM Studio and ML applications
      # These provide libcudart.so, libcudnn.so, etc. for dynamically linked binaries
      cudaPackages.cuda_cudart
      cudaPackages.cudnn
      cudaPackages.libcublas
      cudaPackages.libcufft
    ];
  };
}
