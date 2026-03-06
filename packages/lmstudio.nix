{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
}:

stdenv.mkDerivation rec {
  pname = "lmstudio";
  version = "0.4.6-1";

  src = fetchurl {
    url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
    sha256 = "1yaz5i5qdf2nb7llaml2g3wdck2mwpgpw8kyr787ma5777iplxhl";
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    # Create output directories
    mkdir -p $out/bin
    mkdir -p $out/libexec

    # Copy AppImage
    cp $src $out/libexec/LM-Studio-${version}-x64.AppImage
    chmod +x $out/libexec/LM-Studio-${version}-x64.AppImage

    # Simple wrapper for GUI (CLI has 32-bit library issues on NixOS)
    makeWrapper $out/libexec/LM-Studio-${version}-x64.AppImage $out/bin/lm-studio \
      --argv0 "lm-studio" \
      --run "cd /tmp"

    runHook postInstall
  '';

  meta = with lib; {
    description = "LM Studio - Easy to use desktop app for experimenting with local and open-source Large Language Models (v0.4.6-1, GUI works on NixOS, CLI has 32-bit library issues)";
    homepage = "https://lmstudio.ai/";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = with maintainers; [ ];
    mainProgram = "lm-studio";
    # Note: GUI works, CLI requires 32-bit libraries (libz.so.1 ELFCLASS32) not available on NixOS
    # Use llama.cpp as alternative for CLI operations
  };
}
