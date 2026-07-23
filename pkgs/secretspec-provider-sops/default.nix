{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

# secretspec-provider-sops — SOPS provider backend for SecretSpec.
#
# Source: /home/j_kro/Projects/secretspec (closure of the four-phase
# sops-nix → SecretSpec migration in this repo's previous turns).
# Tracks the public mirror at github.com/reverb256/secretspec-provider-sops;
# once crates.io has the crate, switch this to `rustPlatform.buildRustPackage
# { … src = fetchCrate { … }; }`.

let
  src = fetchFromGitHub {
    owner = "reverb256";
    repo = "secretspec-provider-sops";
    # v0.1.0 release tag (published 2026-07-26).
    # Hash computed via:
    #   nix-prefetch-github reverb256 secretspec-provider-sops --rev v0.1.0
    rev = "v0.1.0";
    hash = "sha256-jiGWoSYLKYPJ4bmW9s1mkpmMHTI1xJGW22kMNSrLn8g=";
  };
in
rustPlatform.buildRustPackage {
  pname = "secretspec-provider-sops";
  version = "0.1.0";
  inherit src;

  # Use the upstream Cargo.lock verbatim (no vendor hash needed).
  cargoLock = {
    lockFile = "${src}/provider-rust/Cargo.lock";
  };

  # Tests require sops/age subprocesses on PATH; the upstream CI runs them
  # against `nix profile install nixpkgs#sops ...`. Skip in this build to
  # keep the NixOS-side closure `nix build`-able without a build-env hint.
  doCheck = false;

  meta = {
    description = "SOPS provider backend for SecretSpec — yaml+json+dotenv+binary format quartet via sops --decrypt";
    longDescription = ''
      Phase 2 closure of the sops-nix → SecretSpec migration. Ships a CLI
      binary (`secretspec-provider-sops get <file> <key> --format yaml`
      / `doctor` / `--help`) plus a `SopsFileProvider` adapter for
      SecretSpec's Provider trait surface (awaiting cachix/secretspec#98
      acceptance).
    '';
    homepage = "https://github.com/reverb256/secretspec-provider-sops";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
