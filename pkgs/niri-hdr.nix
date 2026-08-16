{ lib, fetchFromGitHub, rustPlatform, pkg-config, libdisplay-info, libglvnd, libinput, libxkbcommon, libgbm, pango, seatd, wayland, dbus, pipewire, systemd, eudev, niri-unstable }:

# HDR-enabled niri fork. Base: dividebysandwich/niri @ hdr-smithay-master
# (2516a83b) + reverb256/niri-hdr-fork commit 5f30907: re-probe HDR caps on
# DrmScanEvent::Changed. Fixes TVs that gain HDR capability after connect
# (EDID PQ flip) — previously frozen as SDR for the whole session, which
# made gamescope report SDR output (grayed in-game HDR toggle).
#
# The fork's Cargo.toml patches smithay via a LOCAL path (../smithay, dev
# layout). We replace that with a git [patch] to the dividebysandwich smithay
# fork (which carries the connector color-state / color-management work the
# HDR tty.rs code needs).
#
# NOTE (2026-08-07): the fork's committed Cargo.lock has NO git-source entries
# (it is stale vs the git smithay deps), so the first real build must regenerate
# cargo deps. If buildRustPackage/cargoLock chokes, switch to
#   cargoDeps = rustPlatform.fetchCargoTarball { inherit src; } + cargoVendorDir
# (fetchCargoTarball resolves git deps itself). This is a build-iteration
# concern for the sentry build session, not a src/hash problem.
let
  smithaySrc = fetchFromGitHub {
    owner = "dividebysandwich";
    repo = "smithay";
    rev = "57c805c8e6d0b34601b07d89053b376905008d8a";
    hash = "sha256-sYvo5fPPrf6y2vFI8TbgTfTfNxeVEmzTB+BrqGS7l8o=";
  };
in
niri-unstable.overrideAttrs (old: {
  pname = "niri-hdr";
  version = "2026-08-15-reverb256-fork";

  # hdr-smithay-master HEAD (2026-08-07, verified reachable 2026-08-08 — it is
  # the current branch tip). An EARLIER pin (2516a83b3eef5bc0...) was
  # force-pushed away; do not confuse it with the similar-looking rev below.
  src = fetchFromGitHub {
    owner = "reverb256";
    repo = "niri-hdr-fork";
    rev = "6d1107848a81164c27d582706a379177b43f26c7";
    hash = "sha256-O/AfR/V01nkUXKi6wyMVddgs0vGpHMA/asxKWKbDV88=";
  };

  # Replace the fork's path-based smithay [patch] with a git-based one, and
  # swap the stale committed Cargo.lock for the regenerated one (git smithay
  # entries). The Cargo.lock copy MUST happen here: nixpkgs'
  # cargoSetupPostPatchHook (runs after patchPhase) diffs the source
  # Cargo.lock against the vendored one from importCargoLock — a stale lock
  # fails the build with "Cargo.lock is not the same in /build/cargo-vendor-dir".
  postPatch = (old.postPatch or "") + ''
    # Remove the path-based [patch] section and add git-based one
    sed -i '/^\[patch.*\]/,/^\[/d' Cargo.toml
    cat >> Cargo.toml << GOPHER
[patch."https://github.com/Smithay/smithay.git"]
smithay = { git = "https://github.com/dividebysandwich/smithay", rev = "57c805c8e6d0b34601b07d89053b376905008d8a" }
smithay-drm-extras = { git = "https://github.com/dividebysandwich/smithay", rev = "57c805c8e6d0b34601b07d89053b376905008d8a" }
GOPHER
    # Overwrite the fork's stale lock with the regenerated one (git smithay)
    cp ${./niri-hdr-Cargo.lock} Cargo.lock
  '';

  # Regenerated Cargo.lock (2026-08-07): the fork's committed lock is stale
  # (zero git-source entries). Regenerated via `cargo generate-lockfile` on the
  # patched Cargo.toml (git smithay patch applied) — pins smithay +
  # smithay-drm-extras from the dividebysandwich/smithay fork at 57c805c8.
  # Update: apply the same postPatch to a fork checkout, run
  #   cargo generate-lockfile
  # and replace ./niri-hdr-Cargo.lock.
  #
  # importCargoLock is used directly rather than the `cargoLock` attrset: the
  # attrset doesn't survive overrideAttrs on a buildRustPackage result in this
  # nixpkgs (make-derivation stringifies drv args, sets can't be coerced), while
  # `cargoDeps` is a derivation and coerces to its store path safely.
  # outputHashes keys are "${pkg.name}-${pkg.version}" in this nixpkgs.
  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ./niri-hdr-Cargo.lock;
    outputHashes = {
      # narHash of the dividebysandwich/smithay checkout @ 57c805c8 (no .git);
      # both workspace members share repo+rev → same hash.
      "smithay-0.7.0" = "sha256-sYvo5fPPrf6y2vFI8TbgTfTfNxeVEmzTB+BrqGS7l8o=";
      "smithay-drm-extras-0.1.0" = "sha256-sYvo5fPPrf6y2vFI8TbgTfTfNxeVEmzTB+BrqGS7l8o=";
    };
  };

  meta = old.meta // {
    description = "HDR-enabled niri fork (dividebysandwich hdr-smithay-master)";
  };
})
