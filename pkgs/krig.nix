{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  ...
}: let
  inherit (stdenv) mkDerivation;
in
  mkDerivation rec {
    pname = "krig";
    version = "1.1.1";

    src = fetchurl {
      url = "https://github.com/kryptex-miners-org/kryptex-miners/releases/download/krig-1-1-1/krig-miner-${version}-linux-x64.tar.gz";
      sha256 = "7e10d18aceefe6f9314228563ce68022e572a05c65fca3bf9a7f776b05e14955";
    };

    nativeBuildInputs = [autoPatchelfHook makeWrapper];
    buildInputs = [stdenv.cc.cc.lib];

    installPhase = ''
      mkdir -p $out/bin
      tar -xzf $src
      cp krig-miner $out/bin/krig-miner
      chmod +x $out/bin/krig-miner

      # Krig dlopen()s libcuda.so at runtime for the CUDA backend. Wrap so the
      # NixOS OpenGL driver lib is on the search path (mirrors the peakminer
      # service's LD_LIBRARY_PATH=/run/opengl-driver/lib).
      wrapProgram $out/bin/krig-miner \
        --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib
    '';

    meta = with lib;
      description = "Krig — Kryptex PRL (Pearl) GPU miner for NVIDIA/AMD";
      homepage = "https://github.com/kryptex-miners-org/kryptex-miners";
      license = licenses.unfree;
      platforms = platforms.linux;
  }
