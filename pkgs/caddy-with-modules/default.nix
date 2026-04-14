{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go,
}:
buildGoModule rec {
  pname = "caddy-with-modules";
  version = "2.11.2";
  src = ./src;
  proxyVendor = true;
  vendorHash = "sha256-yBO71Rp+DGP5RiE1S4bMA5HBiPYCYOsslv2UItEI20o=";
  postInstall = ''
    mkdir -p $out/bin
    mv caddy-custom $out/bin/caddy-with-modules
  '';
  buildFlags = [
    "-ldflags=-s -w -X github.com/caddyserver/caddy/v2/cmd.version=${version}"
    "-mod=vendor"
  ];
  preBuild = ''
    export GOSUMDB=off
  '';
  buildPhase = ''
    runHook preBuild
    echo "Building Caddy with custom modules..."
    go build "-mod=mod" "-ldflags=-s -w -X github.com/caddyserver/caddy/v2/cmd.version=${version}" -o caddy-custom
    if [ -f caddy-custom ]; then
      echo "✓ Build successful"
    else
      echo "✗ Build failed"
      exit 1
    fi
    runHook postBuild
  '';
  doCheck = false;
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
