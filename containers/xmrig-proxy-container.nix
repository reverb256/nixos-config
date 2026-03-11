# Nix-based Container Image for xmrig-proxy
# Builds a working container image using the same binary that works on bare metal
{
  pkgs,
  xmrig-proxy,
}:
pkgs.dockerTools.buildImage {
  name = "xmrig-proxy";
  tag = "nixos-latest";

  # Copy the xmrig-proxy binary that works on bare metal
  copyToRoot = pkgs.buildEnv {
    name = "xmrig-proxy-root";
    paths = [
      xmrig-proxy
      pkgs.bash
      pkgs.coreutils
      pkgs.cacert
    ];
    pathsToLink = ["/bin" "/etc" "/lib"];
  };

  # Set up the configuration
  config = {
    Cmd = [
      "/bin/xmrig-proxy"
      "--config=/etc/xmrig-proxy/config.json"
      "--no-color"
    ];

    ExposedPorts = {
      "3333/tcp" = {}; # Stratum port
      "8081/tcp" = {}; # API port
    };

    Env = [
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "PATH=/bin"
    ];
  };
}
