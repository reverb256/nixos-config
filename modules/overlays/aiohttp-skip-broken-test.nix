# Cluster-wide overlay: skip aiohttp tests by patching the package
# directly. We use overrideAttrs at the nixpkgs level to ensure the
# override applies regardless of which Python attribute path is used.

final: prev: {
  # Override aiohttp in all Python package sets. The recursive override
  # in python3.pkgs ensures lix's internal references pick up the patch.
  python310Packages = prev.python310Packages // {
    aiohttp = prev.python310Packages.aiohttp.overridePythonAttrs (old: {
      dontCheck = true;
    });
  };
  python311Packages = prev.python311Packages // {
    aiohttp = prev.python311Packages.aiohttp.overridePythonAttrs (old: {
      dontCheck = true;
    });
  };
  python312Packages = prev.python312Packages // {
    aiohttp = prev.python312Packages.aiohttp.overridePythonAttrs (old: {
      dontCheck = true;
    });
  };
  python313Packages = prev.python313Packages // {
    aiohttp = prev.python313Packages.aiohttp.overridePythonAttrs (old: {
      dontCheck = true;
    });
  };

  # python3.pkgs is exposed via makeScope which uses extends pattern.
  # To override something INSIDE makeScope, we must use extend on the pkgs
  # set itself. prev.python3.pkgs.overrideScope(...) returns a NEW pkgs
  # set with the override applied. Replace python3.pkgs with this.
  python3 = prev.python3 // {
    pkgs = prev.python3.pkgs.overrideScope (self: super: {
      aiohttp = super.aiohttp.overridePythonAttrs (old: { dontCheck = true; });
    });
  };
}
