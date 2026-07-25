{
  lib,
  rustPlatform,
  inputs,
  ...
}:
# secretspec-provider-sops — SOPS provider backend for SecretSpec.
#
# Phase 1a (2026-07-25): Now sourced from `inputs.secretspec-provider-sops`
# flake input only. The previous upstream-cachix fallback (fetchFromGitHub)
# has been removed. The cluster's secretspec build requires the flake input
# to be resolvable.
#
# Both binaries are built:
#   $out/bin/secretspec-provider-sops            (CLI: get / doctor)
#   $out/bin/secretspec-provider-sops-protocol   (NDJSON stdio dispatcher for cachix fork)
let
  forkSrc = inputs.secretspec-provider-sops;
  src = lib.cleanSource (toString forkSrc + "/provider-rust");
  lockFile = toString forkSrc + "/provider-rust/Cargo.lock";
in
rustPlatform.buildRustPackage {
  pname = "secretspec-provider-sops";
  version = "0.1.0";
  inherit src;
  cargoLock = { inherit lockFile; };
  doCheck = false;
  meta = {
    description = "SOPS provider backend for SecretSpec — yaml+json+dotenv+binary format quartet + NDJSON stdio dispatcher per cachix/secretspec#98";
    longDescription = ''
      Phase 2 closure of the sops-nix → SecretSpec migration. The two binaries built into the same closure:
      • secretspec-provider-sops — CLI subcommands get / doctor.
      • secretspec-provider-sops-protocol — long-running NDJSON stdio dispatcher per cachix/secretspec#98.
      The cachix fork's SopsProvider spawns the protocol binary and pipes NDJSON request/response over stdio.
    '';
    homepage = "https://github.com/reverb256/secretspec-provider-sops";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
