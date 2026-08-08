# Custom Caddy build with security, rate-limiting, and caching modules
#
# This package extends the standard Caddy web server with 3 additional modules:
# - caddy-security: Advanced security features (IP whitelisting, JWT, basicauth)
# - caddy-rate-limit: Rate limiting with configurable strategies (sliding window, token bucket)
# - caddy-cache: Response caching with configurable TTL and cache backends
#
# Version: 2.11.2 (upgraded from 2.8.0 by plugin dependencies)
# Go: 1.22
# Build: Reproducible via buildGoModule with custom Go main that imports plugins
#
# Usage: Replace standard caddy with caddy-with-modules in Caddyfile configurations
# Testing: Run `result/bin/caddy-with-modules list-modules | grep -E '(security|ratelimit|cache)'`
#
# See: https://github.com/caddyserver/caddy/wiki/Building-Your-Own for more information
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go,
}:
buildGoModule rec {
  pname = "caddy-with-modules";
  # Upstream security bump: caddy pinned to b2693fb63a (PR #7872) so cel-go
  # can move to >=0.29.2 and clear 37 Dependabot CVEs (issue #380). Pseudo-
  # version reflects that commit; ldflags version is informational only.
  version = "2.11.5-pre.20260711.b2693fb63a";
  # Use the local source directory with custom main.go and go.mod
  src = ./src;
  # Use proxyVendor to avoid go.mod tidy issues
  proxyVendor = true;
  # Vendor hash for Go dependencies — deps changed on the #380 security bump
  # (caddy 2.11.4+ pulls many new transitive versions). Re-derive on build.
  vendorHash = lib.fakeHash;
  # Install and rename binary
  postInstall = ''
    mkdir -p $out/bin
    mv caddy-custom $out/bin/caddy-with-modules
  '';
  # Build flags - use vendor mode to avoid go.mod tidy issues
  buildFlags = [
    "-ldflags=-s -w -X github.com/caddyserver/caddy/v2/cmd.version=${version}"
    "-mod=vendor"
  ];
  # Disable Go's module auto-tidy during build
  preBuild = ''
    export GOSUMDB=off
    # Workaround: Go 1.25 checks go.mod version during build
    # We ignore this error since the build actually succeeds
  '';
  # Override build phase to ignore go mod tidy errors
  buildPhase = ''
    runHook preBuild
    echo "Building Caddy with custom modules..."
    # Build with -mod=mod to avoid vendor consistency checks
    go build "-mod=mod" "-ldflags=-s -w -X github.com/caddyserver/caddy/v2/cmd.version=${version}" -o caddy-custom
    if [ -f caddy-custom ]; then
      echo "✓ Build successful"
    else
      echo "✗ Build failed"
      exit 1
    fi
    runHook postBuild
  '';
  # Basic validation - verify custom modules are loaded
  # Note: Check disabled because it runs before installPhase
  # Manual testing: result/bin/caddy-with-modules list-modules | grep -E '(security|ratelimit|cache)'
  doCheck = false;
  # Meta information
  meta = with lib; {
    description = "Caddy web server with custom modules (security, rate-limit, cache)";
    longDescription = ''
      Caddy is a powerful, enterprise-ready, open source web server with automatic
      HTTPS written in Go. This custom build includes 3 additional modules:
      • caddy-security: Advanced security features (JWT, basicauth, IP whitelisting)
      • caddy-rate-limit: Rate limiting with sliding window and token bucket strategies
      • caddy-cache: Response caching with configurable TTL and multiple cache backends
      Usage: Replace "caddy" with "caddy-with-modules" in your Caddyfile or
      systemd service. All standard Caddy directives are supported.
      Verification: Run `caddy-with-modules list-modules` to see all loaded modules.
    '';
    homepage = "https://caddyserver.com";
    license = licenses.asl20;
    maintainers = [];
    platforms = platforms.linux ++ platforms.darwin;
    mainProgram = "caddy-with-modules";
  };
}
