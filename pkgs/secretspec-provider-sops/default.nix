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
    # Pin to the first v0.1.x release tag once it exists. Until then,
    # bump the rev to a known-good commit SHA on origin/main.
    rev = "v0.1.0";
    # lib.fakeHash allows `nix flake check` to evaluate cleanly; replace
    # with the real SRI once v0.1.0 is tagged:
    #   nix-prefetch-github --owner reverb256 --repo secretspec-provider-sops --rev v0.1.0
    hash = lib.fakeHash;
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
