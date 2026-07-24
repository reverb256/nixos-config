{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  python3,
  ...
}: let
  inherit (stdenv) mkDerivation;
in
  mkDerivation rec {
    pname = "peakminer";
    version = "2.2.2";

    src = fetchurl {
      url = "https://github.com/peakminer/peakminer/releases/download/v${version}/peakminer-${version}.tar.gz";
      sha256 = "6ba96829ce60954e24bd0b626e7f92cb5c7b8b529e3b6616bb189a287ab1d5fa";
    };

    nativeBuildInputs = [autoPatchelfHook makeWrapper];
    buildInputs = [stdenv.cc.cc.lib];

    installPhase = ''
      mkdir -p $out/bin
      mkdir -p $out/share/peakminer

      tar -xzf $src
      cp peakminer/peakminer $out/bin/
      chmod +x $out/bin/peakminer

      # Install auth-translator proxy
      cp ${../pkgs/stratum-auth-translator.py} $out/share/peakminer/stratum-auth-translator.py
      chmod +x $out/share/peakminer/stratum-auth-translator.py

      makeWrapper $out/share/peakminer/stratum-auth-translator.py $out/bin/peakminer-proxy \
        --prefix PATH : ${python3}/bin
    '';

    meta = with lib; {
      description = "PeakMiner GPU cryptocurrency miner";
      homepage = "https://github.com/peakminer/peakminer";
      license = licenses.unfree;
      platforms = platforms.linux;
    };
  }
