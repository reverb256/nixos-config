{ lib, fetchFromGitHub, rustPlatform, pkg-config, libdisplay-info, libglvnd, libinput, libxkbcommon, libgbm, pango, seatd, wayland, dbus, pipewire, systemd, eudev, niri-unstable }:

in
niri-unstable.overrideAttrs (old: {
  pname = "niri-hdr";
  version = "2026-07-25-hdr-fork";

  src = fetchFromGitHub {
    owner = "dividebysandwich";
    repo = "niri";
    # 2026-08-04 audit (WS1): the pinned rev was a TYPO —
    # 2516a83b3eef5bc0… does not exist (GitHub 404). hdr-smithay-master
    # HEAD is 2516a83b3eef5f3a… (same 13-char prefix). Corrected below;
    # hash from `nix-prefetch-url --unpack`.
    rev = "2516a83b3eef5f3a766af5113244357a11e255a6";
    hash = "sha256-1fn45mkmb3kh13i8vmiyhl2k7jacchpsxfsfyh82184v7dnzdib3=";
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
