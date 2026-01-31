{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  glibc,
  zlib,
  gcc-unwrapped,
  libX11,
  libxcb,
  libXext,
  steam-run,
  nvidiaPackages,
}:
stdenv.mkDerivation rec {
  pname = "lolminer";
  version = "1.98a";

  src = fetchurl {
    url = "https://github.com/kryptex-miners-org/kryptex-miners/releases/download/lolminer-1-98a/lolMiner_v1.98a_Lin64.tar.gz";
    sha256 = "0avny9fshray40snp3p90svlijh0mx5dh37fqqqppip9ss9gby72";
  };

  nativeBuildInputs = [autoPatchelfHook];

  buildInputs = [
    glibc
    zlib
    gcc-unwrapped.lib
    libX11
    libxcb
    libXext
    steam-run
    # NVIDIA libraries for GPU mining
    nvidiaPackages.nvidia_x11
  ];

  unpackPhase = ''
    runHook preUnpack
    tar -xf $src
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    mkdir -p $out/lib
    cp ./lolMiner $out/bin/
    chmod +x $out/bin/lolMiner
    
    # Create wrapper script that uses steam-run for proper NVIDIA library loading
    cat > $out/bin/lolMiner << 'EOF'
#!/bin/bash
# Use steam-run to ensure proper NVIDIA library loading in NixOS
exec ${steam-run}/bin/steam-run $out/bin/.lolMiner-wrapped "$@"
EOF
    chmod +x $out/bin/lolMiner
    
    # Use autoPatchelf to fix binary dependencies
    ${autoPatchelfHook} $out/bin/.lolMiner-wrapped
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "NVIDIA/AMD GPU miner with proper library loading";
    homepage = "https://lolminer.org";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
  };
}
