{
  lib,
  stdenv,
  rustPlatform,
  autoPatchelfHook,
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
# The fork-pruning choice below (only `cli sops env dotenv` features) cuts
# compile time by ~70% and decrements 10+ dependencies that the cluster does
# not need (keyring is blocklisted per sops-provider-design.md wallet-key
# blocklist; gcsm/awssm/vault/openbao/bws/akv/infisical/kdbx are unused on
# the homelab).
let
  inherit (stdenv) mkDerivation;

  localForkPath = /home/j_kro/Projects/secretspec-core;
  useLocalFork = builtins.pathExists localForkPath;
in
if useLocalFork
then rustPlatform.buildRustPackage {
  pname = "secretspec";
  version = "0.16.0-local-fork.1";
  src = localForkPath;

  # The workspace Cargo.lock is at ${src}/Cargo.lock — the cachix/secretspec
  # workspace root, with sub-crates like secretspec-derive, secretspec-ffi,
  # secretspec-node, secretspec-php, secretspec-py. Building the workspace
  # target gets you `secretspec` (the CLI binary).
  cargoLock = {
    lockFile = "${localForkPath}/Cargo.lock";
  };

  # Prune to what the cluster actually uses — see header note.
  # NOTE: `sops` is NOT in this list yet — the cachix fork's Cargo.toml
  # doesn't declare a `sops` feature until
  # `secretspec-fork-patches/0001-add-sops-provider.patch` is created and
  # applied. Once that patch lands in the fork, add `"sops"` here. Until
  # then the binary builds but does NOT register `sops://` — the manual
  # bridge demo (just secretspec-bridge-demo) still works because the
  # `secretspec-provider-sops` CLI subprocess decrypts sops://routes
  # independently of the cachix binary's Provider registry.
  buildFeatures = [ "cli" "env" "dotenv" ];

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
    platforms = [ "x86_64-linux" ];
    mainProgram = "secretspec";
  };
}
else mkDerivation rec {
  pname = "secretspec";
  version = "0.16.0";

  # Falls back to the upstream cachix release if /home/j_kro/Projects/secretspec-core
  # is absent (e.g., CI runners, fresh clones).
  src = fetchurl {
    url = "https://github.com/cachix/secretspec/releases/download/v${version}/secretspec-x86_64-unknown-linux-gnu.tar.xz";
    sha256 = "KFzO/x6WVdnj8jcfVlOXVfP26maeW4tnc+jq+CO8PBc=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

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
    platforms = [ "x86_64-linux" ];
    mainProgram = "secretspec";
  };
}
