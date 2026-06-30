{
  lib,
  stdenv,
  version ? "1.0.12",
}: let
  # PeakMiner v1.0.12 - high-performance Pearl (PRL) GPU miner
  # v1.0.12 (2026-06-30): mixed-card fix + big RTX 30-series uplift.
  # Confirmed working on Kryptex PRL pool: shares accepted, named-params auth.
  # NOTE: --legacy-auth (array-form authorize) is broken across ALL versions on
  # Kryptex — connection succeeds, authorize returns true, but shares never flow.
  # The default named-params auth ({"wallet","worker","agent"}) works for shares
  # but Kryptex dashboard groups all connections under "worker" regardless of the
  # worker field in named params. This is a pool-side UI limitation, not a config bug.
  # Statically linked, no library deps. CUDA 12 runtime bundled.
  # 3% dev fee.
  # Vendor the binary to avoid relying on GitHub releases staying up.
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
