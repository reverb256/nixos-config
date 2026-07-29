# Cluster-wide overlay: extend aiohttp's `disabledTests` with the 5 flaky
# tests that fail in our Nix sandboxes. nixpkgs already exposes this
# attribute (see /nix/store/.../python3.13-aiohttp-3.13.5.drv env),
# and pytestArgs with --deselect propagates through all python attribute
# paths that lix resolves (python3.pkgs.aiohttp, python313Packages.aiohttp).
#
# Tests skipped:
#   - test_proxy_*_connection_error: needs real network proxy
#   - test_run_app_preexisting_inet6_socket: needs IPv6 binding (errno 99)
#   - test_test_server_hostnames[::1-::1]: needs ::1 binding (errno 99)
#   - test_tracing test_send: pytest unraisable warning glitch on Py3.13
#
# Without this, nixos-rebuild switch fails because lix depends on aiohttp
# and these 5 tests fail in our sandbox environment.

final: prev: {
  python310Packages = prev.python310Packages // {
    aiohttp = prev.python310Packages.aiohttp.overridePythonAttrs (old: {
      # Append to existing disabledTests (nixpkgs already has some)
      disabledTests = (old.disabledTests or []) ++ [
        "tests/test_proxy_functional.py::test_proxy_http_connection_error"
        "tests/test_proxy_functional.py::test_proxy_https_connection_error"
        "tests/test_run_app.py::test_run_app_preexisting_inet6_socket"
        "tests/test_test_utils.py::test_test_server_hostnames"
        "tests/test_tracing.py::TestTrace::test_send"
      ];
    });
  };
  python311Packages = prev.python311Packages // {
    aiohttp = prev.python311Packages.aiohttp.overridePythonAttrs (old: {
      disabledTests = (old.disabledTests or []) ++ [
        "tests/test_proxy_functional.py::test_proxy_http_connection_error"
        "tests/test_proxy_functional.py::test_proxy_https_connection_error"
        "tests/test_run_app.py::test_run_app_preexisting_inet6_socket"
        "tests/test_test_utils.py::test_test_server_hostnames"
        "tests/test_tracing.py::TestTrace::test_send"
      ];
    });
  };
  python312Packages = prev.python312Packages // {
    aiohttp = prev.python312Packages.aiohttp.overridePythonAttrs (old: {
      disabledTests = (old.disabledTests or []) ++ [
        "tests/test_proxy_functional.py::test_proxy_http_connection_error"
        "tests/test_proxy_functional.py::test_proxy_https_connection_error"
        "tests/test_run_app.py::test_run_app_preexisting_inet6_socket"
        "tests/test_test_utils.py::test_test_server_hostnames"
        "tests/test_tracing.py::TestTrace::test_send"
      ];
    });
  };
  python313Packages = prev.python313Packages // {
    aiohttp = prev.python313Packages.aiohttp.overridePythonAttrs (old: {
      disabledTests = (old.disabledTests or []) ++ [
        "tests/test_proxy_functional.py::test_proxy_http_connection_error"
        "tests/test_proxy_functional.py::test_proxy_https_connection_error"
        "tests/test_run_app.py::test_run_app_preexisting_inet6_socket"
        "tests/test_test_utils.py::test_test_server_hostnames"
        "tests/test_tracing.py::TestTrace::test_send"
      ];
    });
  };
}
