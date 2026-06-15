{
  lib,
  stdenv,
  fetchurl,
  version ? "0.1.9",
  # Kryptex tags sometimes differ from semver (e.g. 0.1.9 → lpminer-0-1-10)
  tag ? "lpminer-${builtins.replaceStrings ["."] ["-"] version}",
}: let
  src = fetchurl {
    url = "https://github.com/kryptex-miners-org/kryptex-miners/releases/download/${tag}/lpminer-${version}.tar.gz";
    hash = "sha256-LpdXrTnboS570gVGqqNUX947O32J4p6vuOq1AOxNF2M=";
  };
in
  stdenv.mkDerivation {
    pname = "lpminer-pearl";
    inherit version src;

    dontUnpack = true;
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
      description = "LPMiner - PearlHash GPU miner";
      homepage = "https://github.com/kryptex-miners-org/kryptex-miners";
      license = lib.licenses.unfree;
      platforms = ["x86_64-linux"];
      maintainers = [];
    };
  }
