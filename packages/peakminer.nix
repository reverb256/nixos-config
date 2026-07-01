{
  lib,
  stdenv,
  fetchurl,
  version ? "1.0.12",
}: let
  # PeakMiner v1.0.12 - high-performance Pearl (PRL) GPU miner
  # v1.0.12 (2026-06-30): mixed-card fix + big RTX 30-series uplift.
  # Confirmed working on Kryptex PRL pool: shares accepted, named-params auth.
  #
  # NOTE: --legacy-auth (array-form authorize) is broken across ALL versions on
  # Kryptex — connection succeeds, authorize returns true, but shares never flow.
  # The default named-params auth ({"wallet","worker","agent"}) works for shares
  # but Kryptex dashboard groups all connections under "worker" regardless of the
  # worker field in named params. This is a pool-side UI limitation, not a config bug.
  #
  # v1.0.11-rc2 NEVER submits shares regardless of flags — avoid.
  #
  # Statically linked, no library deps. CUDA 12 runtime bundled.
  # 3% dev fee.
  #
  # Uses fetchurl from GitHub releases so CI can auto-bump versions.
  src = fetchurl {
    url = "https://github.com/peakminer/peakminer/releases/download/v${version}/peakminer-${version}.tar.gz";
    hash = "sha256-PMpctHDu38FihKNC55Y2Rgd+j6akKBiHUU91imRy0dM=";
  };
in
  stdenv.mkDerivation {
    pname = "peakminer";
    inherit version src;

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      # The tarball extracts to a directory containing the peakminer binary
      # plus HiveOS integration scripts (h-config.sh, h-run.sh, etc.)
      cp peakminer $out/bin/peakminer
      chmod 755 $out/bin/peakminer
      runHook postInstall
    '';

    meta = {
      description = "PeakMiner - high-performance Pearl (PRL) NVIDIA GPU miner";
      homepage = "https://github.com/peakminer/peakminer";
      license = lib.licenses.unfree;
      platforms = ["x86_64-linux"];
      mainProgram = "peakminer";
    };
  }
