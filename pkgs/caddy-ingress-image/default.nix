# Docker image for Caddy Ingress Controller
#
# This image packages the custom Caddy build with security, rate-limiting,
# and caching modules into a container for Kubernetes deployment.
#
# Features:
# - Includes caddy-with-modules binary (5 custom modules)
# - busybox for basic utilities and debugging
# - Exposes ports: 80 (HTTP), 443 (HTTPS), 2019 (Admin API)
# - Volume mounts for config, data, logs, and cache
# - Reproducible builds enabled (deterministic layer hashes)
#
# Usage: Load into Docker with: docker load < result
#        Run with: docker run -p 80:80 -p 443:443 caddy-ingress
#
# Version: 1.0.0
# Build: dockerTools.buildLayeredImage for efficient layering

{
  caddy-with-modules,
  pkgs,
  lib,
}:

pkgs.dockerTools.buildLayeredImage {
  name = "caddy-ingress";
  tag = "latest";

  # Include Caddy binary and busybox for utilities
  contents = [
    caddy-with-modules
    pkgs.busybox
  ];

  # Container configuration
  config = {
    # OCI metadata labels for compliance
    Labels = {
      "org.opencontainers.image.title" = "Caddy Ingress Controller";
      "org.opencontainers.image.description" = "Caddy with security, rate-limiting, and caching modules for Kubernetes";
      "org.opencontainers.image.version" = "1.0.0";
      "org.opencontainers.image.vendor" = "NixOS Cluster";
      "org.opencontainers.image.authors" = "j_kro";
      "org.opencontainers.image.source" = "https://github.com/jkro-nixos/cluster";
    };

    # Run Caddy with default config location
    Cmd = [
      "/bin/caddy-with-modules"
      "run"
      "--adapter"
      "caddyfile"
      "--config"
      "/etc/caddy/Caddyfile"
    ];

    # Expose HTTP, HTTPS, and Admin API ports
    ExposedPorts = {
      "80/tcp" = {};    # HTTP
      "443/tcp" = {};   # HTTPS
      "2019/tcp" = {};  # Admin API
    };

    # Volume mounts for persistence and runtime data
    Volumes = {
      "/etc/caddy" = {};                # Configuration files
      "/data" = {};                     # TLS certificates, Caddy storage
      "/var/log/caddy" = {};            # Access logs
      "/tmp/caddy-rate-limit" = {};     # Rate limiting cache
    };

    # Set working directory
    WorkingDir = "/data";
  };

  # Meta information
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
