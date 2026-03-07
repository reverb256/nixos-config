{ appimageTools
, fetchurl
, lib
, stdenv
}:
let
  extracted = appimageTools.extractType2 {
    pname = "lmstudio";
    version = "0.4.6-1";
    src = fetchurl {
      url = "https://installers.lmstudio.ai/linux/x64/0.4.6-1/LM-Studio-0.4.6-1-x64.AppImage";
      sha256 = "1yaz5i5qdf2nb7llaml2g3wdck2mwpgpw8kyr787ma5777iplxhl";
    };
  };
in
stdenv.mkDerivation {
  pname = "lmstudio";
  version = "0.4.6-1";

  src = extracted;

  dontConfigure = true;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Create directory structure
    mkdir -p $out/bin \
             $out/share/applications \
             $out/share/icons/hicolor/512x512/apps \
             $out/share/icons/hicolor/256x256/apps \
             $out/share/icons/hicolor/128x128/apps \
             $out/share/icons/hicolor/64x64/apps \
             $out/share/icons/hicolor/0x0/apps \
             $out/share/pixmaps

    # Copy the AppImage wrapper
    cp ${extracted}/lm-studio $out/bin/lmstudio
    chmod +x $out/bin/lmstudio

    # Copy the icon from the extracted AppImage
    ICON_SRC="${extracted}/usr/share/icons/hicolor/0x0/apps/lm-studio.png"
    cp $ICON_SRC $out/share/icons/hicolor/0x0/apps/lm-studio.png
    cp $ICON_SRC $out/share/icons/hicolor/512x512/apps/lm-studio.png
    cp $ICON_SRC $out/share/icons/hicolor/256x256/apps/lm-studio.png
    cp $ICON_SRC $out/share/icons/hicolor/128x128/apps/lm-studio.png
    cp $ICON_SRC $out/share/icons/hicolor/64x64/apps/lm-studio.png
    cp $ICON_SRC $out/share/pixmaps/lm-studio.png

    # Copy and patch the desktop entry (use relative icon name for standard lookup)
    cat ${extracted}/lm-studio.desktop > $out/share/applications/lmstudio.desktop
    substituteInPlace $out/share/applications/lmstudio.desktop \
      --replace-fail "Exec=AppRun --no-sandbox %U" "Exec=$out/bin/lmstudio %F"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Easy to use desktop app for local LLMs";
    homepage = "https://lmstudio.ai";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "lmstudio";
  };
}
