# Alpine-based XMRig container image
# Static binary on Alpine 3.21 — ~20MB vs 81MB for xmrig-nixos
{
  pkgs,
  lib,
  ...
}:
let
  version = "6.25.0";
  # Static binary — no glibc needed, runs on Alpine musl
  xmrigSrc = pkgs.fetchurl {
    url = "https://github.com/kryptex-miners-org/kryptex-miners/releases/download/xmrig-6-25-0/xmrig-${version}-linux-static-x64.tar.gz";
    hash = "sha256-BrZTSVVw3cPcrFB8TeTdR6pxdEyyw/Li00+c7N+Oh7M=";
  };
in
pkgs.dockerTools.buildLayeredImage {
  name = "xmrig-alpine";
  tag = version;
  contents = [
    pkgs.dockerTools.caCertificates
  ];
  extraCommands = ''
    # Create minimal Alpine-like structure
    mkdir -p usr/local/bin etc/ssl/certs
    # Extract static xmrig binary
    tar -xzf ${xmrigSrc}
    cp xmrig usr/local/bin/xmrig
    chmod +x usr/local/bin/xmrig
  '';
  config = {
    Entrypoint = [ "/usr/local/bin/xmrig" ];
    WorkingDir = "/";
    Env = [
      "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
    ];
  };
}
