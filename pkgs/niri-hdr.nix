{
  lib,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  libdisplay-info,
  libglvnd,
  libinput,
  libxkbcommon,
  libgbm,
  pango,
  seatd,
  wayland,
  dbus,
  pipewire,
  systemd,
  eudev,
  niri-unstable,
  writeText,
  # Instrumentation toggle (default off — normal production build).
  # Set true for a diagnosis/tuning build: full debug symbols, debug
  # assertions, and a distinct `-instrumented` version tag. Used with
  # RUST_LOG=debug/trace at runtime (the fork already ships tracing with
  # release_max_level_debug) to debug the HDR/color pipeline.
  enableInstrumentation ? false,
}:
# HDR-enabled niri fork: reverb256/niri-hdr-fork @ hdr-latest (980aa465) —
# latest upstream niri (60628446) + full HDR support (rebased from
# dividebysandwich) + re-probe HDR caps on DrmScanEvent::Changed (fixes TVs
# that gain HDR capability after connect, EDID PQ flip — previously frozen as
# SDR for the whole session, so gamescope reported SDR output and grayed the
# in-game HDR toggle).
#
# The fork's Cargo.toml pins smithay DIRECTLY via git to our maintained fork
# reverb256/smithay @ hdr-modern (4c4317bb, color-management APIs on current
# smithay mainline 4cf0b620) — no local-path [patch] section anymore, so no
# sed surgery in postPatch. The only postPatch left is swapping the fork's
# stale committed Cargo.lock for the regenerated one (git smithay entries).
#
# cargoDeps uses importCargoLock directly rather than the `cargoLock` attrset:
# the attrset doesn't survive overrideAttrs on a buildRustPackage result in
# this nixpkgs (make-derivation stringifies drv args, sets can't be coerced),
# while `cargoDeps` is a derivation and coerces to its store path safely.
# outputHashes keys are "${pkg.name}-${pkg.version}" in this nixpkgs.
let
  # Cargo profile override for the instrumented build. Plain TOML via
  # writeText (in scope from args) — referenced by the postPatch below.
  cargoInstrumentedConfig = writeText "cargo-config-instrumented.toml" ''
    [profile.release]
    debug = 2
    debug-assertions = true
    [profile.release.package."*"]
    opt-level = 1
  '';

  smithaySrc = fetchFromGitHub {
    owner = "reverb256";
    repo = "smithay";
    rev = "4c4317bbf51514986a8a2921689fcc516ccfd927";
    hash = "sha256-633ReKCzn1n3gapbkZBOptlTdmFzdMKDHNpDiUSoR44=";
  };
in
  niri-unstable.overrideAttrs (old: {
    pname = "niri-hdr";

    # hdr-latest branch tip (2026-08-15): latest upstream niri + full HDR.
    src = fetchFromGitHub {
      owner = "reverb256";
      repo = "niri-hdr-fork";
      rev = "1442b738dc2cb6cb11fca36a32129c92e79ad8c8";
      hash = "sha256-YQwVMHeYNnbrwT29QFZq11EfjlZ1TKm6HEGm60vSR6s=";
    };

    # Fork tests (cargo test) fail in the headless Nix sandbox (need display/
    # fontconfig/GPU). The compositor binary is what we ship; skip the suite.
    doCheck = false;

    # The fork's Cargo.toml already carries direct git pins to reverb256/smithay
    # (hdr-modern 4c4317bb) — no [patch] surgery needed. Only swap the fork's
    # stale committed Cargo.lock for the regenerated one (git smithay entries).
    # The copy MUST happen here: nixpkgs' cargoSetupPostPatchHook (runs after
    # patchPhase) diffs the source Cargo.lock against the vendored one from
    # importCargoLock — a stale lock fails the build with "Cargo.lock is not the
    # same in /build/cargo-vendor-dir".
    # x86-64-v3: all fleet CPUs support AVX2 + SSE4.2 + popcnt. target-cpu
    # lets rustc emit v3-native instructions (avx2, bmi2, fma, etc.) across
    # the niri + smithay dependency tree — compositor, DRM/KMS, rendering.
    # NB: MUST merge into the base package's env.RUSTFLAGS (which carries
    # rustc link args from buildRustPackage). Setting RUSTFLAGS directly as
    # an overrideAttrs attr makes it a derivation ARG, which overlaps the
    # env attr -> "env attribute set cannot contain attributes passed to
    # derivation" (verified 2026-08-16, collab w/ parallel agent).
    env = old.env // {
      RUSTFLAGS = (old.env.RUSTFLAGS or "") + " -C target-cpu=x86-64-v3";
    };

    # Instrumented build (enableInstrumentation=true): full debug symbols
    # (debug=2 vs upstream's line-tables-only), debug-assertions on, and a
    # distinct version tag so the store path identifies this build.
    # Cargo profile.release is patched via .cargo/config.toml (created with
    # writeText above) so rustc applies it workspace-wide (niri + smithay).
    postPatch =
      (old.postPatch or "")
      + ''
        cp ${./niri-hdr-Cargo.lock} Cargo.lock
      ''
      + lib.optionalString enableInstrumentation ''
        cp ${cargoInstrumentedConfig} .cargo/config.toml
      '';
    version = if enableInstrumentation
      then "2026-08-15-reverb256-fork-instrumented"
      else "2026-08-15-reverb256-fork";

    # Regenerated Cargo.lock (2026-08-15) from the fork checkout (hdr-latest
    # 980aa465): `nix develop --command cargo generate-lockfile` — pins smithay
    # + smithay-drm-extras from reverb256/smithay @ 4c4317bb.
    cargoDeps = rustPlatform.importCargoLock {
      lockFile = ./niri-hdr-Cargo.lock;
      outputHashes = {
        # narHash of the reverb256/smithay checkout @ 4c4317bb (no .git);
        # both workspace members share repo+rev → same hash.
        "smithay-0.7.0" = "sha256-prxUzP2Kf5YYmmUmjmTPMWHOx7wM/Fz5tH18BkQ7okU=";
        "smithay-drm-extras-0.1.0" = "sha256-prxUzP2Kf5YYmmUmjmTPMWHOx7wM/Fz5tH18BkQ7okU=";
      };
    };

    meta =
      old.meta
      // {
        description = "HDR-enabled niri fork (reverb256 hdr-latest + reverb256/smithay hdr-modern)";
      };
  })
