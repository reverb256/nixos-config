{
  pkgs,
  xmrig-proxy,
}:
pkgs.dockerTools.buildImage {
  name = "xmrig-proxy";
  tag = "nixos-latest";
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
  config = {
    Cmd = [
      "/bin/xmrig-proxy"
      "--config=/etc/xmrig-proxy/config.json"
      "--no-color"
    ];
    ExposedPorts = {
      "3333/tcp" = {};
      "8081/tcp" = {};
    };
    Env = [
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "PATH=/bin"
    ];
  };
}
