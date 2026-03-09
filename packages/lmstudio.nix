{
  appimageTools,
  fetchurl,
  lib,
}: let
  version = "0.4.6-1";
  src = fetchurl {
    url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
    sha256 = "1yaz5i5qdf2nb7llaml2g3wdck2mwpgpw8kyr787ma5777iplxhl";
  };

  # Extract the icon from the AppImage first
  appimageContents = appimageTools.extractType2 {
    pname = "lmstudio";
    inherit version src;
  };
in
  appimageTools.wrapType2 {
    pname = "lmstudio";
    inherit version src;

    extraPkgs = _pkgs: [];

    extraInstallCommands = ''
          # Install the icon from the extracted AppImage
          mkdir -p $out/share/icons/hicolor/512x512/apps
          cp ${appimageContents}/lm-studio.png $out/share/icons/hicolor/512x512/apps/lm-studio.png

          # Also install to scalable location for compatibility
          mkdir -p $out/share/icons/hicolor/scalable/apps
          cp ${appimageContents}/lm-studio.png $out/share/icons/hicolor/scalable/apps/lm-studio.png

          # Create desktop file with correct StartupWMClass
          mkdir -p $out/share/applications
          cat > $out/share/applications/lmstudio.desktop << 'EOF'
      [Desktop Entry]
      Name=LM Studio
      Comment=Easy to use desktop app for local LLMs
      GenericName=LM Studio
      Exec=lm-studio %F
      Icon=lm-studio
      Type=Application
      Categories=Development;Science;AI;IDE;
      StartupNotify=true
      StartupWMClass=LM Studio
      Terminal=false
      X-MultipleArgs=false
      MimeType=application/json;
      EOF
    '';

    meta = with lib; {
      description = "Easy to use desktop app for local LLMs";
      homepage = "https://lmstudio.ai";
      license = licenses.unfree;
      platforms = ["x86_64-linux"];
      mainProgram = "lmstudio";
    };
  }
