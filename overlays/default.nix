# Split from the historic monolith `overlay.nix` so sub-interests are reviewable
# and image/package/service concerns no longer share one large surface.
{ inputs }: _final: prev:
let
  inherit (prev.lib) callPackage fetchurl;
in
{
  system = import ./system.nix { inherit inputs _final prev; };
  python = import ./python.nix { inherit inputs _final prev; };
  images = import ./images.nix { inherit inputs _final prev; };
  hardware = import ./hardware.nix { inherit inputs _final prev; };
  apps = import ./apps.nix { inherit inputs _final prev; };
}
