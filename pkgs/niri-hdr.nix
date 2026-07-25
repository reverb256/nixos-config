{ lib, fetchFromGitHub, rustPlatform, pkg-config, libdisplay-info, libglvnd, libinput, libxkbcommon, libgbm, pango, seatd, wayland, dbus, pipewire, systemd, eudev, niri-unstable }:

let
  smithaySrc = fetchFromGitHub {
    owner = "dividebysandwich";
    repo = "smithay";
    rev = "57c805c8e6d0b34601b07d89053b376905008d8a";
    hash = lib.fakeHash;
  };
in
niri-unstable.overrideAttrs (old: {
  pname = "niri-hdr";
  version = "2026-07-25-hdr-fork";

  src = fetchFromGitHub {
    owner = "dividebysandwich";
    repo = "niri";
    rev = "2516a83b3eef5bc053bf5f3f7e0ec3b9a96c4ae5";
    hash = lib.fakeHash;
  };

  # Patch Cargo.toml to use forked smithay instead of local path
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
