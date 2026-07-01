{ stdenv, fetchurl, autoPatchelfHook, lib, python3, ... }:

stdenv.mkDerivation rec {
  pname = "peakminer";
  version = "1.0.12";

  src = fetchurl {
    url = "https://github.com/peakminer/peakminer/releases/download/v${version}/peakminer-${version}-linux-x86_64.tar.gz";
    sha256 = lib.fakeHash;
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/lib
    mkdir -p $out/share/peakminer

    cp peakminer $out/bin/
    chmod +x $out/bin/peakminer

    # Install auth-translator proxy
    cp ${../pkgs/stratum-auth-translator.py} $out/share/peakminer/stratum-auth-translator.py
    chmod +x $out/share/peakminer/stratum-auth-translator.py

    # Wrapper script for proxy
    cat > $out/bin/peakminer-proxy <<'EOF'
    #!${python3}/bin/python3
    exec ${python3}/bin/python3 $out/share/peakminer/stratum-auth-translator.py "$@"
    EOF
    chmod +x $out/bin/peakminer-proxy
  '';

  meta = with lib; {
    description = "PeakMiner GPU cryptocurrency miner";
    homepage = "https://github.com/peakminer/peakminer";
    license = licenses.unfree;
    platforms = platforms.linux;
  };
}