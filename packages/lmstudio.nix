{
  appimageTools,
  fetchurl,
  lib,
  runCommandLocal,
}: let
  version = "0.4.6-1";
  src = fetchurl {
    url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
    sha256 = "1yaz5i5qdf2nb7llaml2g3wdck2mwpgpw8kyr787ma5777iplxhl";
  };
  # Extract AppImage contents
  appimageContents = appimageTools.extractType2 {
    pname = "lmstudio";
    inherit version src;
  };
  # Strip CPU and Vulkan backends from extracted contents to save RAM.
  # LM Studio spawns worker processes for EVERY backend found, eating ~600MB+ even idle.
  # We only want NVIDIA CUDA on this machine (zephyr has constant OOM with 31GB RAM).
  strippedContents = runCommandLocal "lmstudio-${version}-stripped" {} ''
    cp -r ${appimageContents} $out
    chmod -R u+w $out
    BACKENDS=$out/resources/app/.webpack/bin/extensions/backends
    if [ -d "$BACKENDS" ]; then
      # Remove CPU-only backends (avx2 without nvidia)
      for d in "$BACKENDS"/llama.cpp-linux-x86_64-avx2-*; do
        [ -d "$d" ] && echo "$d" | grep -v nvidia && rm -rf "$d" || true
      done
      # Remove Vulkan backends
      rm -rf "$BACKENDS"/llama.cpp-linux-x86_64-vulkan-*
      # Remove Vulkan vendor libs
      rm -rf "$BACKENDS"/vendor/linux-llama-vulkan-vendor-v1
    fi
    echo "[lmstudio] Stripped CPU/Vulkan backends from AppImage"
  '';
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
