{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  nvidia_x11,
  version ? "3.3.4",
}: let
  src = fetchurl {
    url = "https://github.com/doktor83/SRBMiner-Multi/releases/download/${version}/SRBMiner-Multi-${builtins.replaceStrings ["."] ["-"] version}-Linux.tar.gz";
    sha256 = "a69ea5c9c803eff5114986795552870d329afeb558c3591762dbd90636358544";
  };
in
  stdenv.mkDerivation {
    pname = "srbminer-multi";
    inherit version;

    inherit src;

    nativeBuildInputs = [makeWrapper];

    buildInputs = [nvidia_x11];

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out/bin
      tar -xzf $src -C $out --strip-components=1
      chmod +x $out/bin/SRBMiner-MULTI
      # Create wrapper with NVIDIA libs
      makeWrapper $out/bin/SRBMiner-MULTI $out/bin/srbminer \
        --set LD_LIBRARY_PATH "${nvidia_x11}/lib${
        if lib.stdenv.isLinux
        then ":${nvidia_x11}/lib/nvidia"
        else ""
      }"
    '';

    meta = {
      description = "SRBMiner-Multi - GPU/CPU miner for various algorithms";
      homepage = "https://github.com/doktor83/SRBMiner-Multi";
      license = lib.licenses.unfree;
      platforms = ["x86_64-linux"];
      maintainers = [];
    };
  }
