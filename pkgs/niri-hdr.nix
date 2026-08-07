{ lib, fetchFromGitHub, rustPlatform, pkg-config, libdisplay-info, libglvnd, libinput, libxkbcommon, libgbm, pango, seatd, wayland, dbus, pipewire, systemd, eudev, niri-unstable }:

# HDR-enabled niri fork (dividebysandwich/niri @ hdr-smithay-master).
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
  version = "2026-08-07-hdr-fork";

  # Current hdr-smithay-master HEAD (2026-08-07). The previously pinned rev
  # 2516a83b3eef5bc0... is UNREACHABLE — the fork branch was force-pushed.
  src = fetchFromGitHub {
    owner = "dividebysandwich";
    repo = "niri";
    rev = "2516a83b3eef5f3a766af5113244357a11e255a6";
    hash = "sha256-Y8X2bTuboCAQ9E67ri9kTMkzBYU+1o3iCHCOVWctxLo=";
  };

  # Replace the fork's path-based smithay [patch] with a git-based one.
  postPatch = (old.postPatch or "") + ''
    # Remove the path-based [patch] section and add git-based one
    sed -i '/^\[patch.*\]/,/^\[/d' Cargo.toml
    cat >> Cargo.toml << GOPHER
[patch."https://github.com/Smithay/smithay.git"]
smithay = { git = "https://github.com/dividebysandwich/smithay", rev = "57c805c8e6d0b34601b07d89053b376905008d8a" }
smithay-drm-extras = { git = "https://github.com/dividebysandwich/smithay", rev = "57c805c8e6d0b34601b07d89053b376905008d8a" }
GOPHER
  '';

  # The fork may have different lock file — let cargo recompute
  cargoLock = old.cargoLock or null;

  meta = old.meta // {
    description = "HDR-enabled niri fork (dividebysandwich hdr-smithay-master)";
  };
})
