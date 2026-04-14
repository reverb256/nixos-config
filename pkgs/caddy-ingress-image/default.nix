{
  caddy-with-modules,
  pkgs,
  lib,
}:
pkgs.dockerTools.buildLayeredImage {
  name = "caddy-ingress";
  tag = "latest";
  contents = [
    caddy-with-modules
    pkgs.busybox
  ];
  config = {
    Labels = {
      "org.opencontainers.image.title" = "Caddy Ingress Controller";
      "org.opencontainers.image.description" = "Caddy with security, rate-limiting, and caching modules for Kubernetes";
      "org.opencontainers.image.version" = "1.0.0";
      "org.opencontainers.image.vendor" = "NixOS Cluster";
      "org.opencontainers.image.authors" = "j_kro";
      "org.opencontainers.image.source" = "https://github.com/jkro-nixos/cluster";
    };
    Cmd = [
      "/bin/caddy-with-modules"
      "run"
      "--adapter"
      "caddyfile"
      "--config"
      "/etc/caddy/Caddyfile"
    ];
    ExposedPorts = {
      "80/tcp" = {};
      "443/tcp" = {};
      "2019/tcp" = {};
    };
    Volumes = {
      "/etc/caddy" = {};
      "/data" = {};
      "/var/log/caddy" = {};
      "/tmp/caddy-rate-limit" = {};
    };
    WorkingDir = "/data";
  };
  meta = with lib; {
    description = "Docker image for Caddy Ingress Controller with custom modules";
    longDescription = ''
      Caddy Ingress Controller image for Kubernetes deployment. This image
      includes the custom Caddy build with security, rate-limiting, and caching
      modules.
      Features:
      • Automatic HTTPS with Let's Encrypt
      • Advanced security (JWT, basicauth, IP whitelisting)
      • Rate limiting (sliding window, token bucket)
      • Response caching with configurable TTL
      • Admin API on port 2019 for metrics and configuration
      Volume Mounts:
      • /etc/caddy - Caddyfile configuration
      • /data - TLS certificates and storage
      • /var/log/caddy - Access logs
      • /tmp/caddy-rate-limit - Rate limit cache
      Exposed Ports:
      • 80 - HTTP
      • 443 - HTTPS
      • 2019 - Admin API
    '';
    license = licenses.asl20;
    maintainers = [];
    platforms = platforms.linux;
  };
}
