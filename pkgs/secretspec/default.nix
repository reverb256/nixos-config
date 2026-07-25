{
  lib,
  stdenv,
  rustPlatform,
  inputs,
  ...
}:
# secretspec — declarative secrets resolution framework.
#
# Phase 1a (2026-07-25): The cachix-fork secretspec is now a flake input
# (`inputs.secretspec`, declared in flake.nix). The earlier upstream-cachix
# tarball fallback path has been removed — the cluster's secretspec build
# now requires the flake input to be resolvable. The previous
# `builtins.pathExists localForkPath` probe + auto-fallback dual-build is
# gone. CI runners / fresh-clone hosts without the fork should declare their
# own `inputs.secretspec` pointing to upstream cachix/secretspec (or a
# different secretspec fork).
#
# The fork-pruning choice below (only `cli sops` features) cuts compile time
# by ~70% and drops 10+ dependencies that the cluster does not need (keyring
# is blocklisted per sops-provider-design.md wallet-key blocklist;
# gcsm/awssm/vault/openbao/bws/akv/infisical/kdbx are unused on the homelab).
# Providers like `env`/`dotenv`/`onepassword`/`lastpass`/`pass` are always-on
# module declarations in mod.rs (not cfg-gated) and compile unconditionally.
rustPlatform.buildRustPackage {
  pname = "secretspec";
  version = "0.16.0-fork.1";

  # lib.cleanSource walks the flake input directory into a fresh /nix/store
  # path with proper builder-writable perms, filtering .git/, target/,
  # .gitignore'd files.
  src = lib.cleanSource inputs.secretspec;

  # The fork is a Cargo workspace at $src; the secretspec CLI lives
  # in the `secretspec/` subcrate (NOT at workspace root). With
  # `buildAndTestSubdir = "secretspec"`, the build hooks scope cargo to
  # the subcrate so feature resolution consults the subcrate's
  # `secretspec/Cargo.toml` (where `sops` IS declared).
  buildAndTestSubdir = "secretspec";

  # Cargo workspace lock file — the workspace root Cargo.lock covers
  # all subcrates including secretspec-derive, secretspec-ffi, etc.
  cargoLock = {
    lockFile = "${inputs.secretspec}/Cargo.lock";
  };

  # Only build what the cluster needs: the CLI binary and the sops://
  # provider. No-default-features so we don't pull in keyring/kdbx/gcsm/
  # awssm/vault/etc that the homelab doesn't use.
  buildNoDefaultFeatures = true;
  buildFeatures = ["cli" "sops"];

  doCheck = false;

  meta = with lib; {
    description = "Declarative secrets resolution — cluster fork with sops:// subprocess dispatch";
    homepage = "https://github.com/reverb256/secretspec";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "secretspec";
  };
}
