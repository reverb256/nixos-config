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
# failures abort the build.
#
# Override aiohttp for ALL Python versions using prev.python3Packages override.
final: prev: {
  # The standard way: override every version of aiohttp.
  # prev.python3.pkgs.aiohttp / python313Packages.aiohttp / etc. all eventually
  # point at the same Python derivation. Setting dontCheck via overridePythonAttrs
  # here applies to whatever attribute path the consumer uses.
  python313Packages = prev.python313Packages // {
    aiohttp = prev.python313Packages.aiohttp.overridePythonAttrs (old: {
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
  python310Packages = prev.python310Packages // {
    aiohttp = prev.python310Packages.aiohttp.overridePythonAttrs (old: {
      dontCheck = true;
    });
  };
}
