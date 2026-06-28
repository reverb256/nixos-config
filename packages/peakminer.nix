{
  lib,
  stdenv,
  version ? "1.0.8",
}: let
  # PeakMiner v1.0.8 - high-performance Pearl (PRL) GPU miner
  # Claims +14-17% hashrate over lpminer/srbminer on RTX 4060/4070 Ti
  # Statically linked, no library deps. CUDA 12 runtime bundled.
  # 3% dev fee (vs lpminer 0%)
  # Vendor the binary to avoid relying on GitHub releases staying up
  # (learned from lpminer upstream going 404).
  src = ./vendor/peakminer-${version};
in
  stdenv.mkDerivation {
    pname = "peakminer";
    inherit version src;

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out/bin
      install -m755 $src $out/bin/peakminer
    '';

    meta = {
      description = "PeakMiner - high-performance Pearl (PRL) NVIDIA GPU miner";
      homepage = "https://github.com/peakminer/peakminer";
      license = lib.licenses.unfree;
      platforms = ["x86_64-linux"];
      mainProgram = "peakminer";
    };
  }
