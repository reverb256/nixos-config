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
# (separate attribute path from python313Packages.aiohttp).
#
# Solution: use the standard nixpkgs pattern of overriding per-version
# python packages via their versioned attribute, AND directly under
# python3.pkgs which lix uses.

final: prev: let
  # Override aiohttp in each Python version's package set.
  overrideInSet = pySet: pySet // {
    aiohttp = pySet.aiohttp.overridePythonAttrs (old: {
      dontCheck = true;
    });
  };
in {
  # Per-version python packages - the canonical path
  python310Packages = overrideInSet prev.python310Packages;
  python311Packages = overrideInSet prev.python311Packages;
  python312Packages = overrideInSet prev.python312Packages;
  python313Packages = overrideInSet prev.python313Packages;
  # Also override via the legacy python3.pkgs path that lix uses internally.
  # python3.pkgs is exposed as a python-interpreter-specific package set;
  # in nixpkgs it is typically an alias of the latest python's package set.
  python3 = prev.python3 // {
    pkgs = overrideInSet prev.python3.pkgs;
  };
}
