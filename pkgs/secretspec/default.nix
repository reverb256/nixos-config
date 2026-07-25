{
  lib,
  stdenv,
  rustPlatform,
  autoPatchelfHook,
  dbus,
  gcc,
  fetchurl,
  ...
}:
# secretspec — declarative secrets resolution framework (cluster fork source).
#
# Sources (in priority order, picked at evaluation time):
#   1. Local fork at /home/j_kro/Projects/secretspec-core — carries the
#      sops:// subprocess provider patch (see secretspec-fork-patches/0001-add-sops-provider.patch)
#      and the feature/sops-provider-subprocess-dispatch branch. Built with
#      buildRustPackage from the workspace root.
#   2. Upstream v0.16.0 binary tarball from github.com/cachix/secretspec — used
#      when the local fork is absent (CI runners, fresh-clone hosts, anyone
#      who hasn't run `just secretspec-fork-bootstrap`).
#
# IMPURE-EVAL REQUIREMENT: Nix flake pure-eval (the default on
# Lix 2.95.2+ and Nix 2.20+) does not let `builtins.pathExists` probe paths
# outside the flake's directory tree. In pure mode, `builtins.pathExists
# /home/j_kro/Projects/secretspec-core` silently returns `false`, the
# `else mkDerivation` upstream-tarball branch fires, and the resulting
# binary has NO SopsProvider registration (the upstream cachix release
# tarball doesn't ship the sops:// provider; it's an out-of-tree fork
# addition). Every invocation of `nix build` of this derivation MUST pass
# `--option pure-eval false` to select the local-fork branch. Cluster-
# side recipes (`just secretspec-rebuild`, `just secretspec-validate-local`,
# `just deploy <host>`) already do. CI runners and fresh-clone hosts that
# legitimately lack the fork still work fine via the fall-through branch
# (they don't pass `--option pure-eval false` and use the upstream
# tarball — which is acceptable for those environments since they
# wouldn't have the sops:// route to validate anyway).
#
# The fork-pruning choice below (only `cli sops` features via
# cargoBuildFlags --no-default-features) cuts compile time by ~70% and
# decrements 10+ dependencies that the cluster does not need (keyring is
# blocklisted per sops-provider-design.md wallet-key blocklist;
# gcsm/awssm/vault/openbao/bws/akv/infisical/kdbx are unused on the
# homelab). Providers like `env`/`dotenv`/`onepassword`/`lastpass`/`pass`
# are always-on module declarations in mod.rs (not cfg-gated) and compile
# unconditionally.
# Fork SHA pin (Issue #6 / Stream 2c, added 2026-07-25).
# Informational only — the build reads `src = lib.cleanSource localForkPath`,
# not a remote ref. Update via: the secretspec-fork-sha-pin just recipe
# (which runs `git ls-remote <cachix-url>` to capture the fork HEAD SHA
# + prints it). Long-term (Issue #10): when cachix upstream merges + tags
# a release with the sops feature, drop this and let
# `fetchFromGitHub { rev = "vX.Y.Z"; ... }` do the SHA-pinning work natively.
#
# FORK_SHA: unknown / local-only — populate via `just secretspec-fork-sha-pin`.
let
  inherit (stdenv) mkDerivation;

  localForkPath = /home/j_kro/Projects/secretspec-core;
  useLocalFork = builtins.pathExists localForkPath;
in
  if useLocalFork
  then
    rustPlatform.buildRustPackage {
      pname = "secretspec";
      version = "0.16.0-local-fork.2";
      # lib.cleanSource walks the local fork directory into a fresh /nix/store
      # path with proper builder-writable perms, filtering .git/, target/,
      # .gitignore'd files. Same idiom as pkgs/secretspec-provider-sops —without
      # this, buildRustPackage's cargoSetupPostUnpackHook can run into the same
      # "Permission denied" failure on the vendored lockfile copy when sandbox is
      # off and the configured cache happens to inherit restrictive 0555 perms
      # on the cargo-vendor-dir path.
      src = lib.cleanSource localForkPath;
      # workspace root, with sub-crates like secretspec-derive, secretspec-ffi,
      # secretspec-node, secretspec-php, secretspec-py. Building the workspace
      # target gets you `secretspec` (the CLI binary).
      cargoLock = {
        lockFile = "${localForkPath}/Cargo.lock";
      };

      # Prune to what the cluster actually uses — see header note.
      # The cachix fork's Cargo.toml declares `sops = ["tokio/process", ...]`
      # which makes `pub mod sops` (added by
      # `secretspec-fork-patches/0001-add-sops-provider.patch`) compile in.
      # Without this entry, the Nix-built binary registers `env://` and
      # `dotenv://` only — `sops://` routes fall back to the bridge-demo CLI
      # (`just secretspec-bridge-demo`) and `secretspec check --profile
      # production` fails on every annotation that targets an sops:// route.
      #
      # Masking pattern: the `buildFeatures` attribute name in buildRustPackage
      # is NOT consistently honored across this pinned nixpkgs version (commit
      # 9ae611a4); feature names declared in `buildFeatures` that don't match a
      # declared Cargo feature (e.g., `env`, `dotenv` — those are module names,
      # NOT features in the fork's [features] block) get silently dropped along
      # with anything that should have compiled. End result: build succeeds
      # but `pub mod sops` never compiles → runtime reports
      # "Provider backend 'sops' not found". So we route feature propagation
      # through `cargoBuildFlags` directly (the hook appends these verbatim to
      # the `cargo build` invocation), with `--no-default-features` so we don't
      # pull in keyring/kdbx/gcsm/awssm/vault/etc the cluster doesn't use, and
      # `--features cli,sops` to (a) satisfy the [[bin]] `required-features =
      # ["cli"]` gate and (b) fire `pub mod sops`. The always-on provider
      # modules (env/dotenv/onepassword/lastpass/pass/protonpass/
      # systemd_credential/gopass) register unconditionally — they're not
      # gated by cfg anyway, so they're transparently included regardless
      # of this attribute set.
      buildNoDefaultFeatures = true;
      buildFeatures = ["cli" "sops"];

      # The cachix fork is a Cargo workspace at $src; the secretspec CLI lives
      # in the `secretspec/` subcrate (NOT at workspace root). Without this,
      # buildRustPackage runs `cargo build` from the workspace root, where
      # `--features sops` resolves against the workspace root manifest (where
      # it's not declared) and would error out under cargo resolver v2. With
      # `buildAndTestSubdir = "secretspec"`, the build hooks scope cargo to
      # the subcrate so feature resolution consults the subcrate's
      # `secretspec/Cargo.toml` (where `sops` IS declared). The workspace
      # `Cargo.lock` at $src/Cargo.lock is consulted regardless of which
      # subcrate cargo is "in" — see `cargoLock.lockFile` above.
      buildAndTestSubdir = "secretspec";

      # Subprocess tests need sops/age on PATH; we skip them in NixOS closure builds.
      doCheck = false;

      meta = with lib; {
        description = "Declarative secrets resolution — cluster local fork with sops:// subprocess dispatch";
        longDescription = ''
          secretspec decouples declaration (TOML schema) from resolution
          (provider URIs: env://, dotenv://, keyring://, onepassword://, sops://).
          Built from /home/j_kro/Projects/secretspec-core on branch
          feature/sops-provider-subprocess-dispatch (see
          secretspec-fork-patches/0001-add-sops-provider.patch).

          Cluster usage:
            secretspec check  --manifest /etc/nixos/secretspec.toml
            secretspec list   --manifest /etc/nixos/secretspec.toml

          Provider chain (Phase 2): sops -> dotenv -> env. Once the cachix
          fork's `sops` feature lands (patch in
          secretspec-fork-patches/0001-add-sops-provider.patch), the SOPS
          provider spawns the secretspec-provider-sops-protocol binary via
          NDJSON stdio per cachix/secretspec#98 Secret Provider Protocol v1.
        '';
        homepage = "https://github.com/cachix/secretspec";
        license = licenses.asl20;
        platforms = ["x86_64-linux"];
        mainProgram = "secretspec";
      };
    }
  else
    mkDerivation rec {
      pname = "secretspec";
      version = "0.16.1";

      # Falls back to the upstream cachix release if /home/j_kro/Projects/secretspec-core
      # is absent (e.g., CI runners, fresh clones).
      src = fetchurl {
        url = "https://github.com/cachix/secretspec/releases/download/v${version}/secretspec-x86_64-unknown-linux-gnu.tar.xz";
        sha256 = "KFzO/x6WVdnj8jcfVlOXVfP26maeW4tnc+jq+CO8PBc=";
      };

      nativeBuildInputs = [autoPatchelfHook];
      buildInputs = [dbus gcc.cc.lib];

      dontConfigure = true;
      dontBuild = true;

      # The cachix release tarball pulls glibc dynamically; autoPatchelfHook
      # patches rpath in fixupPhase before this installPhase hashes the binary.
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        tar -xJf $src -C $out/bin
        BIN=$(find $out/bin -type f -name secretspec -print -quit)
        if [ -z "$BIN" ]; then
          echo "secretspec binary not found after extraction" >&2
          exit 1
        fi
        install -Dm755 "$BIN" $out/bin/secretspec
        SUBDIR="$(dirname "$BIN")"
        if [ "$SUBDIR" != "$out/bin" ]; then
          rm -rf "$SUBDIR"
        fi
        runHook postInstall
      '';

      meta = with lib; {
        description = "Declarative secrets resolution framework — upstream binary fallback";
        longDescription = ''
          secretspec fetched from upstream cachix/secretspec v0.16.0 release
          tarball. This is the fallback for hosts WITHOUT a local
          ~/Projects/secretspec-core checkout; cluster-side builds see the
          buildRustPackage path above (preferred).
        '';
        homepage = "https://github.com/cachix/secretspec";
        license = licenses.asl20;
        platforms = ["x86_64-linux"];
        mainProgram = "secretspec";
      };
    }
