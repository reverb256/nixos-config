{
  appimageTools,
  fetchurl,
  lib,
  runCommandLocal,
}: let
  version = "0.4.16-1";
  src = fetchurl {
    url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
    sha256 = "sha256-DLB1V7dSkHKlJz6CDaHgFkJxjptdGPL9e33w7ZXR3a8=";
  };
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
      mkdir -p $out/share/icons/hicolor/{512x512,scalable}/apps
      cp ${appimageContents}/lm-studio.png $out/share/icons/hicolor/512x512/apps/lm-studio.png
      cp ${appimageContents}/lm-studio.png $out/share/icons/hicolor/scalable/apps/lm-studio.png
      mkdir -p $out/share/applications
      cat > $out/share/applications/lmstudio.desktop << 'DESKTOP'
      [Desktop Entry]
      Name=LM Studio
      Comment=Local LLMs (GPU-only, NVIDIA CUDA)
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
      DESKTOP
    '';
    meta = with lib; {
      description = "Local LLM runner (GPU-only, NVIDIA CUDA)";
      homepage = "https://lmstudio.ai";
      license = licenses.unfree;
      platforms = ["x86_64-linux"];
      mainProgram = "lmstudio";
    };
  }
