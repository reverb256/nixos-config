{
  lib,
  stdenv,
  version ? "1.0.11-rc2",
}: let
  # PeakMiner v1.0.11-rc2 - high-performance Pearl (PRL) GPU miner
  # Fixes "low hashrate on mixed-card rigs" (release notes 2026-06-29).
  # Cluster topology this targets: 1× RTX 3090 + 2× RTX 4060 + 2× RTX 3060 Ti
  # across zephyr/forge/nexus — previously 0 shared on v1.0.8 despite long uptime.
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
