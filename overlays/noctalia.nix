# Noctalia — track the latest upstream beta from nixpkgs master.
#
# 2026-08-21: PINNED to 5.0.0-beta.8. beta.9's build recipe (same stb'
# workaround, meson flags) keeps failing on librsvg/nodejs deps over the
# remote builders (stream-ended-unexpectedly + interrupted-by-user), and
# beta.8 is the known-good, already-built version running via systemd
# drop-in. Restore this to beta.9 (or later) once upstream or the pinned
# nixpkgs provides a green build.
{ inputs, _final, prev }:
let
  inherit (prev) fetchFromGitHub;
in
{
  noctalia = prev.noctalia.overrideAttrs (old: {
    version = "5.0.0-beta.8";
    src = fetchFromGitHub {
      owner = "noctalia-dev";
      repo = "noctalia";
      tag = "v5.0.0-beta.8";
      hash = "sha256-ISOU1jKxCdvZg0msJi56rg/172PAi9ZYS+BHxIkaY6Q=";
    };
  });
}
