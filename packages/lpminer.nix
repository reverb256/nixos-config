{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  version ? "1.98",
}: let
  src = fetchurl {
    url = "https://github.com/Lolliedieb/lolMiner-releases/releases/download/${version}/lolMiner_v${builtins.replaceStrings ["."] [""] version}_Lin64.tar.gz";
    sha256 = "0hhz3wkz25lizsiljbqz9k9mi8wrnhxmpjpjkv35v1496k6wxdsn";
  };
in
  stdenv.mkDerivation {
    pname = "lpminer";
    inherit version src;

    nativeBuildInputs = [makeWrapper];

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out/bin
      tar -xzf $src
      mv lolMiner $out/bin/
      chmod +x $out/bin/lolMiner
      makeWrapper $out/bin/lolMiner $out/bin/lpminer \
        --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib"
    '';

    meta = {
      description = "lolMiner - Equihash/Autolykos2/kawPow miner";
      homepage = "https://github.com/Lolliedieb/lolMiner-releases";
      license = lib.licenses.unfree;
      platforms = ["x86_64-linux"];
      maintainers = [];
    };
  }
