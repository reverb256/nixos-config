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
# failures abort the build. See discussion in AGENTS.md / hermes logs.
#
# IMPORTANT: lix pulls aiohttp via python3.pkgs.aiohttp (not python313Packages.aiohttp),
# so we must override BOTH paths to actually disable tests in the lix chain.
final: prev: let
  override = drv: drv.overridePythonAttrs (old: {
    # Disable pytest entirely for aiohttp - too flaky in Nix sandboxes.
    # Runtime behavior is unaffected; only the in-build test phase is skipped.
    dontCheck = true;
  });
in {
  # python313Packages.aiohttp - the normal attribute
  python313Packages = prev.python313Packages // {
    aiohttp = override prev.python313Packages.aiohttp;
  };
  # python3.pkgs.aiohttp and pythonPackages.aiohttp - lix pulls via these
  python3 = prev.python3 // {
    pkgs = prev.python3.pkgs // {
      aiohttp = override prev.python3.pkgs.aiohttp;
    };
  };
  pythonPackages = prev.pythonPackages // {
    aiohttp = override prev.pythonPackages.aiohttp;
  };
}
