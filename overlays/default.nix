# Split from the historic monolith `overlay.nix` so sub-interests are reviewable
# and image/package/service concerns no longer share one large surface.
# Each sub-overlay returns an attrset that is merged (//) into the top level
# so that `pkgs.gputemps` (not `pkgs.system.gputemps`) resolves correctly.
{ inputs }: _final: prev:
let
  inherit (prev.lib) foldl';
  bugfixOverlay = import ./bugfixes.nix { inherit inputs _final prev; };
  systemOverlay = import ./system.nix { inherit inputs _final prev; };
  pythonOverlay = import ./python.nix { inherit inputs _final prev; };
  hardwareOverlay = import ./hardware.nix { inherit inputs _final prev; };
  llamaOverlay = import ./llama.nix { inherit inputs _final prev; };
  v3Overlay = import ./x86-64-v3.nix { inherit inputs _final prev; };
  noctaliaOverlay = import ./noctalia.nix { inherit inputs _final prev; };
in
foldl' (acc: overlay: acc // overlay) {} [
  bugfixOverlay
  systemOverlay
  pythonOverlay
  hardwareOverlay
  llamaOverlay
  v3Overlay
  noctaliaOverlay
]
