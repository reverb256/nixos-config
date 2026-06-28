{
  lib,
  stdenv,
  version ? "0.1.9",
}: let
  # Upstream GitHub source went 404 in mid-2026 (kryptex-miners-org repo
  # no longer publishes lpminer releases — only xmrig/wildrig now).
  # The last known-good tarball is vendored in-repo at packages/vendor/.
  # To regenerate from a cached store path:
  #   mkdir -p lpminer && cp /nix/store/*-lpminer-pearl-0.1.9/bin/lpminer lpminer/
  #   tar -czf packages/vendor/lpminer-0.1.9.tar.gz lpminer
  src = ./vendor/lpminer-${version}.tar.gz;
in
  stdenv.mkDerivation {
    pname = "lpminer-pearl";
    inherit version src;

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out/bin
      tar -xzf $src
      # tarball contains lpminer/ directory with binary inside
      chmod +x lpminer/lpminer
      mv lpminer/lpminer $out/bin/
    '';

    meta = {
      description = "LPMiner - PearlHash GPU miner (vendored — upstream removed)";
      homepage = "https://github.com/kryptex-miners-org/kryptex-miners";
      license = lib.licenses.unfree;
      platforms = ["x86_64-linux"];
      maintainers = [];
    };
  }
