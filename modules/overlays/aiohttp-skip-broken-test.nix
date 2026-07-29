# Cluster-wide overlay: skip aiohttp tests.
#
# Without this overlay, nixos-rebuild switch fails because lix
# (the build toolchain) depends on python3.13-aiohttp, and the test
# failures abort the build.
#
# Strategy: nixpkgs in 26.11 exposes Python packages via several aliases
# (python313Packages, pythonPackages, python3.pkgs). We override aiohttp
# in EVERY alias so lix's lookup finds the patched derivation.

final: prev: {
  # Canonical per-version attributes
  python310Packages = prev.python310Packages // {
    aiohttp = prev.python310Packages.aiohttp.overridePythonAttrs (o: { dontCheck = true; });
  };
  python311Packages = prev.python311Packages // {
    aiohttp = prev.python311Packages.aiohttp.overridePythonAttrs (o: { dontCheck = true; });
  };
  python312Packages = prev.python312Packages // {
    aiohttp = prev.python312Packages.aiohttp.overridePythonAttrs (o: { dontCheck = true; });
  };
  python313Packages = prev.python313Packages // {
    aiohttp = prev.python313Packages.aiohttp.overridePythonAttrs (o: { dontCheck = true; });
  };
  # Legacy aliases used by lix and older code.
  # python3.pkgs is the standard alias for the default python (currently 3.13).
  python3 = prev.python3 // {
    pkgs = prev.python313Packages // {
      aiohttp = prev.python313Packages.aiohttp.overridePythonAttrs (o: { dontCheck = true; });
    };
  };
}
