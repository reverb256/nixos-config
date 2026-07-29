# Compatibility shim: kept so existing importers do not break.
# The canonical overlay surface is now `overlays/default.nix`.
{ inputs }: import ./overlays/default.nix { inherit inputs; }
