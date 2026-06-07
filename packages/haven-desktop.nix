{
  appimageTools,
  fetchurl,
  lib,
}: let
  version = "1.2.0";
  src = fetchurl {
    url = "https://github.com/ancsemi/Haven-Desktop/releases/download/v${version}/Haven-${version}.AppImage";
    hash = "sha256-7GRsnwtccDOlhSNntzQYRROF38GPVounLDMWV/4IHEY=";
  };
  appimageContents = appimageTools.extractType2 {
    pname = "haven-desktop";
    inherit version src;
  };
in
  appimageTools.wrapType2 {
    pname = "haven-desktop";
    inherit version src;

    extraPkgs = pkgs: [
      # GPU rendering (Chromium/Electron needs these in the sandbox)
      pkgs.mesa
      pkgs.libGL
      pkgs.libdrm
      pkgs.libxkbcommon
      pkgs.wayland
      # Audio capture native addon (PulseAudio)
      pkgs.pipewire
      pkgs.pulseaudio
      # X11 fallback
      pkgs.libx11
      pkgs.libxcomposite
      pkgs.libxdamage
      pkgs.libxext
      pkgs.libxfixes
      pkgs.libxrandr
      pkgs.libxcb
      pkgs.libxshmfence
      # Font rendering
      pkgs.fontconfig
      pkgs.freetype
      pkgs.stdenv.cc.cc.lib
    ];

    extraInstallCommands = ''
      # Icon
      mkdir -p $out/share/icons/hicolor/512x512/apps
      cp ${appimageContents}/usr/share/icons/hicolor/512x512/apps/haven-desktop.png \
         $out/share/icons/hicolor/512x512/apps/haven-desktop.png

      # Desktop entry with Wayland + GPU flags
      mkdir -p $out/share/applications
      cat > $out/share/applications/haven-desktop.desktop << 'DESKTOP'
      [Desktop Entry]
      Name=Haven
      Comment=Private chat, reimagined for your desktop
      Exec=haven-desktop --no-sandbox --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations %U
      Icon=haven-desktop
      Type=Application
      Categories=Network;Chat;InstantMessaging;
      StartupNotify=true
      StartupWMClass=Haven
      Terminal=false
      MimeType=x-scheme-handler/haven;
      DESKTOP
    '';

    meta = with lib; {
      description = "Haven Desktop — private chat with per-app audio sharing";
      homepage = "https://github.com/ancsemi/Haven-Desktop";
      license = licenses.agpl3Only;
      platforms = ["x86_64-linux"];
      mainProgram = "haven-desktop";
    };
  }
