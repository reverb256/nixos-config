# Noctalia — track the latest upstream beta from nixpkgs master.
#
# The pinned nixpkgs input ships 5.0.0-beta.8, but upstream
# (noctalia-dev/noctalia) and nixpkgs-unstable are on 5.0.0-beta.9. The
# pinned package's build recipe is byte-identical to master's (same stb'
# workaround, meson flags, build inputs) — only the version + source differ,
# so a surgical override is safe and avoids a full nixpkgs input bump.
# Keep the version/hash in sync with nixpkgs master
# (pkgs/by-name/no/noctalia/package.nix) on future bumps.
{ inputs, _final, prev }:
let
  inherit (prev) fetchFromGitHub;
in
{
  noctalia = prev.noctalia.overrideAttrs (old: {
    version = "5.0.0-beta.9";
    src = fetchFromGitHub {
      owner = "noctalia-dev";
      repo = "noctalia";
      tag = "v5.0.0-beta.9";
      hash = "sha256-O07tHqxugZ/XE/90kx/UCZ0YCbHSI88v2ct2ezuCKi4=";
    };
  });
}
