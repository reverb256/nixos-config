{
  appimageTools,
  fetchurl,
}:
appimageTools.wrapType2 rec {
  pname = "lmstudio";
  version = "0.4.6-1";

  src = fetchurl {
    url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
    sha256 = "1yaz5i5qdf2nb7llaml2g3wdck2mwpgpw8kyr787ma5777iplxhl";
  };

  extraPkgs = pkgs:
    with pkgs; [
      fuse3
      zlib
      glib
      gtk3
    ];
}
