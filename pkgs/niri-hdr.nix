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
  smithaySrc = fetchFromGitHub {
    owner = "reverb256";
    repo = "smithay";
    rev = "4c4317bbf51514986a8a2921689fcc516ccfd927";
    hash = "sha256-633ReKCzn1n3gapbkZBOptlTdmFzdMKDHNpDiUSoR44=";
  };
in
  niri-unstable.overrideAttrs (old: {
    pname = "niri-hdr";
    version = "2026-08-15-reverb256-fork";

    # hdr-latest branch tip (2026-08-15): latest upstream niri + full HDR.
    src = fetchFromGitHub {
      owner = "reverb256";
      repo = "niri-hdr-fork";
      rev = "980aa465258a29c7c49cc2e2b55194e83a4efbf4";
      hash = "sha256-clwvdKg6XjfWNfGy0kcuix3u/c4aaT5TSmEpL4sTOOM=";
    };

    # The fork's Cargo.toml already carries direct git pins to reverb256/smithay
    # (hdr-modern 4c4317bb) — no [patch] surgery needed. Only swap the fork's
    # stale committed Cargo.lock for the regenerated one (git smithay entries).
    # The copy MUST happen here: nixpkgs' cargoSetupPostPatchHook (runs after
    # patchPhase) diffs the source Cargo.lock against the vendored one from
    # importCargoLock — a stale lock fails the build with "Cargo.lock is not the
    # same in /build/cargo-vendor-dir".
    postPatch =
      (old.postPatch or "")
      + ''
        cp ${./niri-hdr-Cargo.lock} Cargo.lock
      '';

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
