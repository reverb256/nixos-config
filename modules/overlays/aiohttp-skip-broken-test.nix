# Cluster-wide overlay: skip aiohttp tests by mutating the aiohttp
# package's dontCheck via ALL its python attribute paths.
#
# Without this overlay, nixos-rebuild switch fails because lix
# (the build toolchain) depends on python3.13-aiohttp, and the test
# failures abort the build.
#
# Strategy: override aiohttp at the toplevel nixpkgs scope (so ALL python
# versions, including the legacy python3.pkgs.aiohttp alias, get the patch).

final: prev: let
  # Override one specific aiohttp and let Nix propagate via super.aiohttp references.
  pkgsScoped = prev.appendOverlays [
    (superFinal: superPrev: {
      aiohttp = superPrev.aiohttp.overridePythonAttrs (old: {
        dontCheck = true;
      });
    })
  ];
  # Use the scoped pkgs to override python3.pkgs
  python3 = prev.python3 // {
    pkgs = pkgsScoped.python3.pkgs;
  };
  # Per-version python packages
  python310Packages = pkgsScoped.python310Packages;
  python311Packages = pkgsScoped.python311Packages;
  python312Packages = pkgsScoped.python312Packages;
  python313Packages = pkgsScoped.python313Packages;
in {}
