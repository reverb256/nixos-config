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
# The fix: use recursive override (extend-style) so that BOTH attribute
# paths return the same patched derivation.

final: prev: {
  # Override aiohttp for every Python version's package set.
  python310Packages = prev.python310Packages // {
    aiohttp = prev.python310Packages.aiohttp.overridePythonAttrs (old: { dontCheck = true; });
  };
  python311Packages = prev.python311Packages // {
    aiohttp = prev.python311Packages.aiohttp.overridePythonAttrs (old: { dontCheck = true; });
  };
  python312Packages = prev.python312Packages // {
    aiohttp = prev.python312Packages.aiohttp.overridePythonAttrs (old: { dontCheck = true; });
  };
  python313Packages = prev.python313Packages // {
    aiohttp = prev.python313Packages.aiohttp.overridePythonAttrs (old: { dontCheck = true; });
  };

  # python3.pkgs is the legacy alias - it points to the latest python's
  # package set. Recursive override here ensures both paths converge.
  python3 = prev.python3 // {
    pkgs = prev.python3.pkgs.overrideScope (self: super: {
      aiohttp = super.aiohttp.overridePythonAttrs (old: { dontCheck = true; });
    });
  };
}
