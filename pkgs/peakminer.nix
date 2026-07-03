{ lib, stdenv, fetchurl, autoPatchelfHook, makeWrapper, python3, ... }:
let
  inherit (stdenv) mkDerivation;
in
mkDerivation rec {
  pname = "peakminer";
  version = "1.0.13";

  src = fetchurl {
    url = "https://github.com/peakminer/peakminer/releases/download/v${version}/peakminer-${version}.tar.gz";
    sha256 = "a6d677e1270d1c8a3abb343dd79bef4c8adb6765b5fb6cee10b06cd719b51d81";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
  buildInputs = [ stdenv.cc.cc.lib ];

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
