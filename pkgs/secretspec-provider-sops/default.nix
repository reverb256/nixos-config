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
    # Audit 2026-07-26 -- documented-fallback path applied.
    #
    # The v0.1.0 release tag has not been published upstream yet (literal
    # `nix-prefetch-github --owner reverb256 --repo secretspec-provider-sops
    # --rev v0.1.0` cannot run today). Applying the fallback from
    # /home/j_kro/Projects/secretspec/CONTEXT.md
    # (Audit 2026-07-23 -- lib.fakeHash SRI upstream precondition check,
    #  Recommended next step section):
    #   * `rev` bumped to a known-good commit SHA on origin/main
    #     (24e4813bb0d418ab93630e55710615aa32965cd5).
    #   * `hash` replaced with the NAR hash of that SHA's tarball,
    #     computed via `nix-prefetch-url --unpack` and converted to SRI
    #     via `nix hash to-sri ...`.
    #
    # To migrate once v0.1.0 is tagged upstream, replace rev with "v0.1.0"
    # and re-run:
    #   nix-prefetch-github --owner reverb256 --repo secretspec-provider-sops --rev v0.1.0
    rev = "24e4813bb0d418ab93630e55710615aa32965cd5";
    hash = "sha256-LdNi3L7jJJWZ3eTIbIzTfFSJSKa4Ant8ZdB7K/qKabI";
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
