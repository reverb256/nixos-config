# Builds the homelab Lix package — the derivation wired into
# `nix.package` on every cluster host (see modules/system/nix-config.nix).
# Extracted so the lix-vm-test (tests/lix-vm.nix) exercises EXACTLY what
# the cluster runs, without importing the whole nix-config module (whose
# nixpkgs.config / overlay definitions clash with the NixOS test
# framework).
#
# The 4 homelab patches are IN-TREE on the `homelab/2.96` branch of the
# pinned `lix` flake input (see flake.nix): the fork source IS the
# patched tree, so this derivation applies no patches of its own. The
# overrides below are nixpkgs-packaging concerns (deps the 2.95-era glue
# lacks, test suites disabled for the sandbox) plus per-host CPU tuning.
{
  pkgs,
  inputs,
  microarch,
}:
let
  # Version of the Lix source we build from, read from the pinned `lix`
  # flake input (e.g. "2.96.0-dev"). Keep in sync with the source tree.
  lixVersion = (builtins.fromJSON (builtins.readFile "${inputs.lix}/version.json")).version;
in
(pkgs.lixPackageSets.lix_2_95.lix.overrideAttrs (old: {
  # 2026-07-29: lix's FileTransfer unit tests fail in our sandbox with
  # errno 99 (Cannot assign requested address). Disable lix's own test
  # suite via its native enable-tests meson option.
  # 2026-08-14 (Lix checkout test): the 2.95-era `dontCheck = true` was a
  # no-op — nixpkgs' lix glue sets `doCheck = true`, and this nixpkgs rev's
  # setup.sh only skips the check phase when doCheck is empty (dontCheck
  # is never consulted). Without doCheck=false the check phase runs
  # `cargo test`, which fails to link with gcc ('-shared-libsan' is
  # clang-only, injected via CXX_TEST_SANITIZERS when b_sanitize is set).
  doCheck = false;
  doInstallCheck = false;
  # Lix exposes -Denable-tests=false as a meson build option (see
  # https://github.com/lix-project/lix/blob/main/meson.options).
  # This disables the test() calls in lix's meson.build entirely.
  mesonFlags = (old.mesonFlags or []) ++ [
    "-Denable-tests=false"
    # 2026-08-14 (Lix checkout test): 2.96.0-dev regressed contrib plugin
    # builds — contrib/plugins/meson.build switched to
    # liblix.partial_dependency() on Linux, dropping the ninja dependency
    # on the zngur codegen target, so plugin_mtls_store.cc fails with
    # 'lix/lix-rs/zngur.gen.hh' not found. Unfixed on current main
    # (c60a53d1d..2c5e3461); the cluster does not use contrib plugins.
    "-Denable-contrib-plugins=false"
  ];

  # --- Performance tuning (homelab fork) ---
  # Tag the fork so `nix --version` and store paths are distinguishable
  # from pristine upstream ${lixVersion} AND from each other host's -march
  # build (all four share the post-build cache, so per-host naming matters).
  # Lix's meson.build composes the version as `version.json + $VERSION_SUFFIX`;
  # nixpkgs' common-lix.nix already plumbed env.VERSION_SUFFIX = suffix.
  __intentionallyOverridingVersion = true;
  version = "${lixVersion}-homelab-${microarch}";

  # 2026-08-14 (Lix checkout test): build from the pinned `lix` flake
  # input instead of nixpkgs' pristine 2.95.2 tarball. All the nixpkgs
  # build glue (clang stdenv, meson flags, curl-fixed, python fixups)
  # stays in place; only the source + its cargo lock change.
  src = inputs.lix;
  # 2.96.0-dev links mimalloc by default (meson option `mimalloc`, value
  # auto) — a dependency nixpkgs' 2.95-era common-lix.nix does not
  # provide. Add it explicitly so meson picks it up.
  buildInputs = (old.buildInputs or []) ++ [pkgs.mimalloc];
  # 2.96.0-dev's book.toml uses the linkcheck2 backend (mdbook-linkcheck2),
  # which nixpkgs' 2.95-era glue does not put on PATH — the manual build
  # fails with 'mdbook-linkcheck2' wasn't found. cacert is required too:
  # linkcheck wants a root cert to exist even when it never hits the
  # network (matches lix's own package.nix).
  nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
    pkgs.mdbook-linkcheck2
    pkgs.cacert
  ];
  # Cargo.lock moved since 2.95.2, so the pinned cargoDeps no longer
  # matches — vendor a fresh tarball for THIS source.
  cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
    name = "lix-${lixVersion}-cargo-deps";
    src = inputs.lix;
    # Real hash computed from the pinned source's Cargo.lock
    # (2026-08-14, first-build iteration).
    hash = "sha256-hZJGpMnnsk++/OfkAxJ+fVWOK3WqhDiWVqANtdeKcOM=";
  };

  # The 4 homelab patches (Boehm GC heap cap, attr-set linear scan,
  # zngur codegen ordering, lix-rs test gating) are now IN-TREE on the
  # `homelab/2.96` branch of the pinned `lix` input (see flake.nix) —
  # the fork source IS the patched tree, so this list stays empty and
  # nixpkgs' applyPatches never double-applies. The fixes above (mimalloc,
  # mdbook-linkcheck2 + cacert, doCheck=false, contrib-plugins off) are
  # nixpkgs-packaging concerns, not source patches, so they remain here.
  patches = old.patches or [];

  # Tune Lix to this host's CPU. This nixpkgs rev's cc-wrapper has a
  # SINGLE compile-flag channel: NIX_CFLAGS_COMPILE is injected into both
  # C and C++ invocations (the C++ stdlib flags are even appended into
  # it, see cc-wrapper.sh/add-flags.sh). NIX_CXXFLAGS_COMPILE no longer
  # exists, so don't bother setting it. -march tunes the C++ evaluator /
  # store (the hot path). -O3 is safe here because Lix is built with
  # clangStdenv (the upstream "-O3 angers a gcc bug" note is gcc-only);
  # LTO is already enabled upstream via -Db_lto=true. Drop -O3 if it
  # ever regresses a build.
  env = (old.env or {}) // {
    VERSION_SUFFIX = "-homelab-${microarch}";
    NIX_CFLAGS_COMPILE = "${old.env.NIX_CFLAGS_COMPILE or ""} -march=${microarch} -O3";
    # The Rust crates (lix-rs, lix-doc) build via cargo, which does NOT
    # read NIX_CFLAGS_COMPILE. Give them the same per-host microarch.
    # Append (not overwrite) so any nixpkgs default isn't clobbered.
    #
    # CAVEAT: RUSTFLAGS also applies to proc-macro / build-script crates
    # that EXECUTE on the build host during compilation. If nexus (znver2)
    # builds a host's znver3 Lix, a proc-macro emitting znver3-only
    # instructions could SIGILL mid-build. Drop RUSTFLAGS (or build the
    # per-host variant on that host) if the znver3-for-nexus build breaks.
    RUSTFLAGS = "${old.env.RUSTFLAGS or ""} -C target-cpu=${microarch}";
  };
}))
