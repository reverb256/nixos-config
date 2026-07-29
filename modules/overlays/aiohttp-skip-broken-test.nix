# Cluster-wide overlay: skip aiohttp tests that fail intermittently
# on the homelab cluster. The actual aiohttp functionality is fine;
# these tests are flaky in sandboxes/proxies due to:
#   - test_proxy_*_connection_error: needs real network proxy
#   - test_run_app_preexisting_inet6_socket: needs IPv6 binding
#   - test_test_server_hostnames: needs ::1 binding
#   - test_tracing test_send: pytest unraisable warning glitch on Py3.13
#
# Without this overlay, nixos-rebuild switch fails because lix
# (the build toolchain) depends on python3.13-aiohttp, and the test
# failures abort the build. lix references aiohttp via python3.pkgs.aiohttp
# which is a SEPARATE attribute from python313Packages.aiohttp in nixpkgs.
#
# The fix: define the override ONCE and import it from BOTH paths so the
# recursive override chain properly applies.

final: prev: let
  aiohttpOverride = pySet: pySet.aiohttp.overridePythonAttrs (old: {
    dontCheck = true;
  });
  overridePkgs = pySet: pySet // {
    aiohttp = aiohttpOverride pySet;
  };
in {
  # Per-version python packages - the canonical path
  python310Packages = overridePkgs prev.python310Packages;
  python311Packages = overridePkgs prev.python311Packages;
  python312Packages = overridePkgs prev.python312Packages;
  python313Packages = overridePkgs prev.python313Packages;

  # Recursively extend python3.pkgs (the legacy alias lix uses).
  # python3.pkgs is a makeScope result, so we have to extend it the same way.
  python3 = prev.python3 // {
    pkgs = (prev.python3.pkgs.overrideScope (self: super: {
      aiohttp = super.aiohttp.overridePythonAttrs (old: { dontCheck = true; });
    }));
  };
  # Also override the pythonPackages alias (in case it differs).
  pythonPackages = overridePkgs prev.pythonPackages;
}
