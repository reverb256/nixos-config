{
  appimageTools,
  fetchurl,
  lib,
  makeWrapper,
}:

let
  package = appimageTools.wrapType2 rec {
    pname = "lmstudio";
    version = "0.4.6-1";

    src = fetchurl {
      url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
      sha256 = "1yaz5i5qdf2nb7llaml2g3wdck2mwpgpw8kyr787ma5777iplxhl";
    };

    extraPkgs = pkgs: with pkgs; [
      fuse3
      zlib
    ];

    meta = with lib; {
      description = "LM Studio - Easy to use desktop app for experimenting with local and open-source Large Language Models (v0.4.6-1)";
      homepage = "https://lmstudio.ai/";
      license = licenses.unfree;
      platforms = [ "x86_64-linux" ];
      maintainers = with maintainers; [ ];
    };
  };
in
package.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ makeWrapper ];

  postBuild = (old.postBuild or "") + ''
    # Wrap lmstudio binary as lm-studio
    makeWrapper ${package}/bin/lmstudio $out/bin/lm-studio \
      --run "cd /tmp"
  '';

  meta = package.meta // {
    mainProgram = "lm-studio";
  };
})
