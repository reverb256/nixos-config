{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
# secretspec-provider-sops — SOPS provider backend for SecretSpec.
#
# Sources (in priority order, picked at evaluation time):
#   1. Local fork at /home/j_kro/Projects/secretspec/provider-rust — the
#      cluster's primary source. 36 commits ahead of upstream, with the
#      NDJSON stdio dispatcher binary already implemented.
#   2. Upstream v0.1.0 tag at github.com/reverb256/secretspec-provider-sops
#      — fallback for CI runners and fresh-clone hosts.
#
# Both binaries are built:
#   $out/bin/secretspec-provider-sops            (CLI: get / doctor)
#   $out/bin/secretspec-provider-sops-protocol   (NDJSON stdio dispatcher for cachix fork)
let
  localForkSubcrate = /home/j_kro/Projects/secretspec/provider-rust;
  remote = fetchFromGitHub {
    owner = "reverb256";
    repo = "secretspec-provider-sops";
    rev = "v0.1.0";
    hash = "sha256-jiGWoSYLKYPJ4bmW9s1mkpmMHTI1xJGW22kMNSrLn8g=";
  };
  sources = if builtins.pathExists localForkSubcrate
    then {
      src = localForkSubcrate;
      lockFile = toString localForkSubcrate + "/Cargo.lock";
    }
    else {
      src = remote;
      lockFile = toString remote + "/provider-rust/Cargo.lock";
    };
in
rustPlatform.buildRustPackage {
  pname = "secretspec-provider-sops";
  version = "0.1.0";
  src = sources.src;
  cargoLock = { lockFile = sources.lockFile; };
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
